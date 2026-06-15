import json
import logging
import secrets
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
        return self._json_response(
            {
                "token": device.token,
                "device": self._device_payload(device),
                "attendance": self._empty_status_payload(),
            }
        )

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
                "threshold": float(self._config("face_attendance.match_threshold", "0.70")),
                "employees": payload,
            }
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
            device.write(vals)
        else:
            device = request.env["face.attendance.device"].sudo().create(vals)

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
        device, error = self._require_device()
        if error:
            return error
        body = self._body()
        accepted = bool(body.get("accepted"))
        matched_employee_id = body.get("matched_employee_id")
        match_score = float(body.get("match_score") or 0.0)
        threshold = float(body.get("threshold") or self._config("face_attendance.match_threshold", "0.70"))
        device_id = body.get("device_id") or device.device_uid
        app_version = body.get("app_version")
        failure_reason = body.get("failure_reason")
        second_best_confidence = body.get("second_best_confidence")
        embedding_source = body.get("embedding_source")
        review_embedding_id = body.get("review_embedding_id")
        needs_review = bool(body.get("needs_review"))
        liveness_passed = bool(body.get("liveness_passed"))
        liveness_score = body.get("liveness_score")
        spoof_score = body.get("spoof_score")
        try:
            second_best_confidence = float(second_best_confidence) if second_best_confidence is not None else False
        except (TypeError, ValueError):
            second_best_confidence = False
        try:
            review_embedding_id = int(review_embedding_id) if review_embedding_id else False
        except (TypeError, ValueError):
            review_embedding_id = False
        try:
            liveness_score = float(liveness_score) if liveness_score is not None else 0.0
        except (TypeError, ValueError):
            liveness_score = 0.0
        try:
            spoof_score = float(spoof_score) if spoof_score is not None else 0.0
        except (TypeError, ValueError):
            spoof_score = 0.0

        now = fields.Datetime.now()
        timestamp_val = body.get("timestamp")
        if timestamp_val:
            try:
                if isinstance(timestamp_val, str):
                    # Replace ISO 'T' and 'Z' to make it compatible with Odoo's datetime parsing
                    clean_ts = timestamp_val.replace('Z', '').replace('T', ' ')
                    now = fields.Datetime.to_datetime(clean_ts)
                else:
                    now = fields.Datetime.to_datetime(timestamp_val)
            except Exception:
                pass

        employee = device.employee_id
        if device.device_type == "scanner":
            employee = None
            if matched_employee_id:
                try:
                    matched_employee_id = int(matched_employee_id)
                except (TypeError, ValueError):
                    return self._json_response({"error": "invalid_matched_employee_id"}, status=400)
                employee = request.env["hr.employee"].sudo().browse(matched_employee_id)
                if not employee.exists():
                    return self._json_response({"error": "matched_employee_not_found"}, status=404)
        if accepted and not employee:
            return self._json_response({"error": "matched_employee_id_required"}, status=400)

        if accepted and not liveness_passed and not failure_reason:
            failure_reason = "liveness_failed"

        log_accepted = bool(employee) and accepted and match_score >= threshold and liveness_passed
        if accepted and employee and match_score < threshold and not failure_reason:
            failure_reason = "below_threshold"

        log = request.env["face.attendance.log"].sudo().create(
            {
                "employee_id": employee.id if employee else False,
                "device_uid": device_id,
                "app_version": app_version,
                "match_score": match_score,
                "threshold": threshold,
                "second_best_confidence": second_best_confidence,
                "embedding_source": embedding_source,
                "review_embedding_id": review_embedding_id,
                "needs_review": needs_review,
                "liveness_passed": liveness_passed,
                "liveness_score": liveness_score,
                "spoof_score": spoof_score,
                "accepted": log_accepted,
                "failure_reason": failure_reason,
                "raw_payload": json.dumps(body),
            }
        )

        if not log.accepted:
            return self._json_response(
                {
                    "accepted": False,
                    "log_id": log.id,
                    "employee": self._employee_payload(employee) if employee else None,
                    "attendance": self._status_payload(employee) if employee else self._empty_status_payload(),
                }
            )

        start_of_day = now.replace(hour=0, minute=0, second=0, microsecond=0)
        end_of_day = now.replace(hour=23, minute=59, second=59, microsecond=999999)

        daily_attendance = request.env["hr.attendance"].sudo().search(
            [("employee_id", "=", employee.id), ("check_in", ">=", start_of_day), ("check_in", "<=", end_of_day)],
            limit=1,
            order="check_in asc",
        )
        if not daily_attendance:
            attendance = request.env["hr.attendance"].sudo().create(
                {
                    "employee_id": employee.id,
                    "check_in": now,
                    "recognition_confidence": match_score,
                    "recognition_method": "face",
                    "face_device_uid": device_id,
                    "face_log_id": log.id,
                }
            )
            punch_type = "check_in"
        else:
            attendance = daily_attendance
            attendance.write(
                {
                    "check_out": now,
                    "recognition_confidence": match_score,
                    "recognition_method": "face",
                    "face_device_uid": device_id,
                    "face_log_id": log.id,
                }
            )
            punch_type = "check_out"

        log.write({"attendance_id": attendance.id, "punch_type": punch_type})
        return self._json_response(
            {
                "accepted": True,
                "punch_type": punch_type,
                "log_id": log.id,
                "employee": self._employee_payload(employee),
                "attendance": self._status_payload(employee),
            }
        )

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
