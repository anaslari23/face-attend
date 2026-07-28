import json
import logging
import secrets
import struct
from datetime import timedelta

from odoo import fields, http
from odoo.http import request

_logger = logging.getLogger(__name__)


class FaceAttendanceController(http.Controller):
    def _json_response(self, payload, status=200):
        return request.make_response(
            json.dumps(payload, default=str),
            headers=[("Content-Type", "application/json")],
            status=status,
        )

    def _body(self):
        raw = request.httprequest.get_data() or b"{}"
        try:
            return json.loads(raw.decode("utf-8"))
        except ValueError:
            return {}

    def _device_from_token(self):
        auth_header = request.httprequest.headers.get("Authorization", "")
        token = auth_header.removeprefix("Bearer ").strip()
        if not token:
            return None
        device = request.env["face.attendance.device"].sudo().search(
            [
                ("token", "=", token),
                ("active", "=", True),
                ("token_expires_at", ">", fields.Datetime.now()),
            ],
            limit=1,
        )
        if not device:
            return None
        device.last_seen_at = fields.Datetime.now()
        return device

    def _employee_from_token(self):
        device = self._device_from_token()
        if not device or device.device_type != "employee":
            return None
        return device.employee_id

    def _require_employee(self):
        employee = self._employee_from_token()
        if not employee:
            return None, self._json_response({"error": "unauthorized"}, status=401)
        return employee, None

    def _require_device(self):
        device = self._device_from_token()
        if not device:
            return None, self._json_response({"error": "unauthorized"}, status=401)
        return device, None

    @http.route("/face_attendance/scanner/setup", type="http", auth="none", methods=["POST"], csrf=False)
    def scanner_setup(self, **kwargs):
        body = self._body()
        setup_code = (body.get("setup_code") or "").strip()
        if not setup_code:
            return self._json_response({"error": "setup_code_required"}, status=400)

        device = request.env["face.attendance.device"].sudo().search(
            [
                ("token", "=", setup_code),
                ("device_type", "=", "scanner"),
                ("active", "=", True),
                ("token_expires_at", ">", fields.Datetime.now()),
            ],
            limit=1,
        )
        if not device:
            return self._json_response({"error": "invalid_scanner_setup_code"}, status=401)

        device.last_seen_at = fields.Datetime.now()
        generated_device_id = None

        device_try_to_connect = body.get("device_try_to_connect")
        if device_try_to_connect:
            existing_line = device.connected_device_line_ids.filtered(lambda l: l.name == device_try_to_connect)
            if not existing_line:
                if len(device.connected_device_line_ids) >= device.devices_can_connect:
                    return self._json_response({"error": "You can't connect with this setup code. Try with another or contact with Administrator."}, status=403)

                import time
                generated_device_id = str(device_try_to_connect)[-4:] + str(int(time.time()))
                request.env["face.attendance.connected.device"].sudo().create({
                    "name": device_try_to_connect,
                    "generated_device_id": generated_device_id,
                    "device_id": device.id
                })
                device.device_try_to_connect = device_try_to_connect
            else:
                generated_device_id = existing_line[0].generated_device_id
                device.device_try_to_connect = device_try_to_connect

        response_data = {
            "token": device.token,
            "device": self._device_payload(device),
            "attendance": self._empty_status_payload(),
        }
        if generated_device_id:
            response_data["generated_device_id"] = generated_device_id

        return self._json_response(response_data)

    @http.route("/face_attendance/scanner/employees", type="http", auth="none", methods=["GET", "POST"], csrf=False)
    def scanner_employees(self, **kwargs):
        device, error = self._require_device()
        if error:
            return error
        if device.device_type != "scanner":
            return self._json_response({"error": "scanner_device_required"}, status=403)

        body = self._body() if request.httprequest.method == "POST" else {}
        model_version = "arcface-w600k-r50-align-v3"
        known_dates = body.get("known_avatar_write_dates") or {}
        allow_incremental = body.get("model_version") == model_version and isinstance(known_dates, dict)

        employees = request.env["hr.employee"].sudo().search(
            [("active", "=", True), ("image_1920", "!=", False)],
            order="id",
        )
        payload = []
        for employee in employees:
            avatar_write_date = fields.Datetime.to_string(employee.write_date)
            known_write_date = str(known_dates.get(str(employee.id)) or known_dates.get(employee.id) or "")
            include_avatar = not allow_incremental or known_write_date != avatar_write_date
            payload.append(
                {
                    "id": employee.id,
                    "name": employee.name,
                    "department": employee.department_id.name if employee.department_id else None,
                    "avatar": (
                        employee.image_1920.decode("utf-8")
                        if isinstance(employee.image_1920, bytes)
                        else employee.image_1920
                    )
                    if include_avatar
                    else "",
                    "avatar_write_date": avatar_write_date,
                    "face_enabled": True,
                }
            )
        return self._json_response(
            {
                "device": self._device_payload(device),
                "model_version": model_version,
                "threshold": device.config_id.confidence_threshold if device.config_id else 0.70,
                "employees": payload,
            }
        )

    @http.route("/face_attendance/scanner/index/manifest", type="http", auth="none", methods=["GET"], csrf=False)
    def scanner_index_manifest(self, **kwargs):
        device, error = self._require_device()
        if error:
            return error
        if device.device_type != "scanner":
            return self._json_response({"error": "scanner_device_required"}, status=403)

        try:
            since = max(0, int(request.httprequest.args.get("since", "0")))
        except ValueError:
            return self._json_response({"error": "invalid_index_revision"}, status=400)
        state = request.env["face.attendance.index.state"].sudo().search([("name", "=", "default")], limit=1)
        revision = state.revision if state else 0
        etag = '"face-index-%s"' % revision
        if since == revision or request.httprequest.headers.get("If-None-Match") == etag:
            return request.make_response(b"", headers=[("ETag", etag)], status=304)

        templates = request.env["face.attendance.template"].sudo().search(
            [("revision", ">", since)], order="revision, id"
        )
        changes = []
        for template in templates:
            enabled = bool(
                template.active
                and template.state == "ready"
                and template.employee_id
                and template.employee_id.active
            )
            changes.append(
                {
                    "employee_id": template.employee_odoo_id,
                    "name": template.employee_name,
                    "department": template.employee_id.department_id.name if enabled and template.employee_id.department_id else None,
                    "revision": template.revision,
                    "enabled": enabled,
                }
            )
        config = device.config_id
        return self._json_response(
            {
                "model_version": "arcface-w600k-r50-align-v3",
                "dimensions": 512,
                "revision": revision,
                "threshold": config.confidence_threshold if config else 0.70,
                "changes": changes,
            },
            status=200,
        )

    @http.route("/face_attendance/scanner/index/chunk", type="http", auth="none", methods=["GET"], csrf=False)
    def scanner_index_chunk(self, **kwargs):
        device, error = self._require_device()
        if error:
            return error
        if device.device_type != "scanner":
            return self._json_response({"error": "scanner_device_required"}, status=403)
        raw_ids = request.httprequest.args.get("ids", "")
        try:
            employee_ids = sorted({int(value) for value in raw_ids.split(",") if value})
        except ValueError:
            return self._json_response({"error": "invalid_employee_ids"}, status=400)
        if not employee_ids or len(employee_ids) > 250:
            return self._json_response({"error": "request_between_1_and_250_employee_ids"}, status=400)
        templates = request.env["face.attendance.template"].sudo().search(
            [
                ("employee_odoo_id", "in", employee_ids),
                ("active", "=", True),
                ("state", "=", "ready"),
                ("employee_id.active", "=", True),
            ],
            order="employee_odoo_id",
        )
        payload = bytearray(struct.pack("!4sI", b"FAI1", len(templates)))
        for template in templates:
            embedding = template.embedding_bytes()
            payload.extend(struct.pack("!I", template.employee_odoo_id))
            payload.extend(embedding)
        return request.make_response(
            bytes(payload),
            headers=[
                ("Content-Type", "application/octet-stream"),
                ("Cache-Control", "no-store"),
            ],
        )

    @http.route("/face_attendance/login", type="http", auth="none", methods=["POST"], csrf=False)
    def login(self, **kwargs):
        body = self._body()
        db = body.get("db") or request.session.db
        login = body.get("login")
        password = body.get("password")
        device_id = body.get("device_id")
        device_name = body.get("device_name")

        if not db or not login or not password or not device_id:
            return self._json_response({"error": "db, login, password and device_id are required"}, status=400)

        try:
            credential = {'login': login, 'password': password, 'type': 'password'}
            auth_info = request.session.authenticate(request.env, credential)
            uid = auth_info['uid']
        except Exception:
            _logger.exception("Face attendance login failed")
            return self._json_response({"error": "invalid_credentials"}, status=401)

        user = request.env["res.users"].sudo().browse(uid)
        employee = request.env["hr.employee"].sudo().search([("user_id", "=", user.id)], limit=1)
        if not employee:
            return self._json_response({"error": "no_employee_linked"}, status=403)

        token = secrets.token_urlsafe(48)
        expires = fields.Datetime.now() + timedelta(days=30)
        device = request.env["face.attendance.device"].sudo().search(
            [("employee_id", "=", employee.id), ("device_uid", "=", device_id)],
            limit=1,
        )
        vals = {
            "employee_id": employee.id,
            "device_type": "employee",
            "device_uid": device_id,
            "name": device_name or device_id,
            "token": token,
            "token_expires_at": expires,
            "active": True,
            "last_seen_at": fields.Datetime.now(),
        }
        if device:
            device.with_user(1).write(vals)
        else:
            device = request.env["face.attendance.device"].with_user(1).sudo().create(vals)

        return self._json_response(
            {
                "token": token,
                "expires_at": expires,
                "employee": self._employee_payload(employee),
                "attendance": self._status_payload(employee),
            }
        )

    @http.route("/face_attendance/enroll", type="http", auth="none", methods=["POST"], csrf=False)
    def enroll(self, **kwargs):
        return self._json_response({"error": "phone_only_scanner_uses_avatar_sync"}, status=410)

    @http.route("/face_attendance/template", type="http", auth="none", methods=["GET"], csrf=False)
    def template(self, **kwargs):
        return self._json_response({"error": "phone_only_scanner_uses_local_embeddings"}, status=410)

    @http.route("/face_attendance/status", type="http", auth="none", methods=["GET"], csrf=False)
    def status(self, **kwargs):
        device, error = self._require_device()
        if error:
            return error
        if device.employee_id:
            return self._json_response(
                {
                    "device": self._device_payload(device),
                    "employee": self._employee_payload(device.employee_id),
                    "attendance": self._status_payload(device.employee_id),
                }
            )
        return self._json_response({"device": self._device_payload(device), "attendance": self._empty_status_payload()})

    @http.route("/face_attendance/punch", type="http", auth="none", methods=["POST"], csrf=False)
    def punch(self, **kwargs):
        try:
            device, error = self._require_device()
            if error:
                return error
            body = self._body()
            config = device.config_id
            accepted = bool(body.get("accepted"))
            matched_employee_id = body.get("matched_employee_id")
            match_score = float(body.get("match_score") or 0.0)
            threshold = config.confidence_threshold if config else 0.70
            failure_reason = body.get("failure_reason")
            second_best_confidence = self._float_or_false(body.get("second_best_confidence"))
            review_embedding_id = self._int_or_false(body.get("review_embedding_id"))
            liveness_score = self._float_or_zero(body.get("liveness_score"))
            spoof_score = self._float_or_zero(body.get("spoof_score"))
            liveness_passed = bool(body.get("liveness_passed"))
            now = self._punch_time(body.get("timestamp"))

            employee = device.employee_id
            if device.device_type == "scanner":
                employee = request.env["hr.employee"]
                if matched_employee_id:
                    employee = request.env["hr.employee"].sudo().browse(self._int_or_false(matched_employee_id))
                if not employee.exists():
                    return self._json_response({"error": "matched_employee_not_found"}, status=404)
            if accepted and not employee:
                return self._json_response({"error": "matched_employee_id_required"}, status=400)

            liveness_ok = liveness_passed or not (config and config.liveness_required)
            log_accepted = bool(employee) and accepted and match_score >= threshold and liveness_ok
            if accepted and not liveness_ok and not failure_reason:
                failure_reason = "liveness_failed"
            if accepted and employee and match_score < threshold and not failure_reason:
                failure_reason = "below_threshold"

            log = request.env["face.attendance.log"].sudo().create({
                "employee_id": employee.id if employee else False,
                "device_uid": device.device_uid,
                "app_version": body.get("app_version"),
                "match_score": match_score,
                "threshold": threshold,
                "second_best_confidence": second_best_confidence,
                "embedding_source": body.get("embedding_source"),
                "review_embedding_id": review_embedding_id,
                "needs_review": bool(body.get("needs_review")),
                "liveness_passed": liveness_passed,
                "liveness_score": liveness_score,
                "spoof_score": spoof_score,
                "accepted": log_accepted,
                "failure_reason": failure_reason,
                "punch_time": now,
            })
            if not log.accepted:
                return self._json_response({"accepted": False, "log_id": log.id, "employee": self._employee_payload(employee) if employee else None, "attendance": self._status_payload(employee) if employee else self._empty_status_payload()})
            return self._json_response({"accepted": True, "punch_type": log.punch_type, "log_id": log.id, "employee": self._employee_payload(employee), "attendance": self._status_payload(employee)})
        except Exception:
            _logger.exception("Punch failed")
            return self._json_response({"error": "punch_failed"}, status=500)

    @staticmethod
    def _float_or_false(value):
        try:
            return float(value) if value is not None else False
        except (TypeError, ValueError):
            return False

    @staticmethod
    def _float_or_zero(value):
        try:
            return float(value) if value is not None else 0.0
        except (TypeError, ValueError):
            return 0.0

    @staticmethod
    def _int_or_false(value):
        try:
            return int(value) if value else False
        except (TypeError, ValueError):
            return False

    @staticmethod
    def _punch_time(value):
        if not value:
            return fields.Datetime.now()
        try:
            return fields.Datetime.to_datetime(value.replace("Z", "").replace("T", " ") if isinstance(value, str) else value)
        except (TypeError, ValueError):
            return fields.Datetime.now()

    def _device_payload(self, device):
        return {
            "id": device.id,
            "name": device.name,
            "device_uid": device.device_uid,
            "device_type": device.device_type,
        }

    def _employee_payload(self, employee):
        return {
            "id": employee.id,
            "name": employee.name,
            "department": employee.department_id.name if employee.department_id else None,
            "face_registered": bool(employee.face_registered),
        }

    def _status_payload(self, employee):
        attendance = request.env["hr.attendance"].sudo().search(
            [("employee_id", "=", employee.id), ("check_out", "=", False)],
            limit=1,
            order="check_in desc",
        )
        return {
            "checked_in": bool(attendance),
            "attendance_id": attendance.id if attendance else None,
            "check_in": attendance.check_in if attendance else None,
        }

    def _empty_status_payload(self):
        return {
            "checked_in": False,
            "attendance_id": None,
            "check_in": None,
        }

    def _config(self, key, default):
        return request.env["ir.config_parameter"].sudo().get_param(key, default)
