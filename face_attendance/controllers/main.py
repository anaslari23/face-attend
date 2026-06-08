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

    def _employee_from_token(self):
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
        return device.employee_id

    def _require_employee(self):
        employee = self._employee_from_token()
        if not employee:
            return None, self._json_response({"error": "unauthorized"}, status=401)
        return employee, None

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
            uid = request.session.authenticate(db, login, password)
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
        employee, error = self._require_employee()
        if error:
            return error
        body = self._body()
        embeddings = body.get("embeddings") or []
        model_version = body.get("model_version") or self._config("face_attendance.model_version", "mobilefacenet-v1")
        device_id = body.get("device_id")
        quality_score = float(body.get("quality_score") or 0.0)

        if len(embeddings) < 3:
            return self._json_response({"error": "at_least_three_embeddings_required"}, status=400)

        normalized = []
        for vector in embeddings:
            if not isinstance(vector, list) or not vector:
                return self._json_response({"error": "invalid_embedding"}, status=400)
            normalized.append([float(value) for value in vector])

        request.env["face.attendance.template"].sudo().search(
            [("employee_id", "=", employee.id), ("active", "=", True)]
        ).write({"active": False})
        template = request.env["face.attendance.template"].sudo().create(
            {
                "employee_id": employee.id,
                "embedding_json": json.dumps(normalized),
                "model_version": model_version,
                "device_uid": device_id,
                "quality_score": quality_score,
                "active": True,
            }
        )
        employee.sudo().write(
            {
                "face_registered": True,
                "face_registered_date": fields.Datetime.now(),
                "face_enrollment_count": employee.face_enrollment_count + 1,
            }
        )
        return self._json_response({"template_id": template.id, "employee": self._employee_payload(employee)})

    @http.route("/face_attendance/template", type="http", auth="none", methods=["GET"], csrf=False)
    def template(self, **kwargs):
        employee, error = self._require_employee()
        if error:
            return error
        template = request.env["face.attendance.template"].sudo().search(
            [("employee_id", "=", employee.id), ("active", "=", True)],
            limit=1,
            order="create_date desc",
        )
        if not template:
            return self._json_response({"template": None, "employee": self._employee_payload(employee)})
        return self._json_response(
            {
                "employee": self._employee_payload(employee),
                "template": {
                    "id": template.id,
                    "model_version": template.model_version,
                    "threshold": float(self._config("face_attendance.match_threshold", "0.82")),
                    "embeddings": json.loads(template.embedding_json or "[]"),
                },
            }
        )

    @http.route("/face_attendance/status", type="http", auth="none", methods=["GET"], csrf=False)
    def status(self, **kwargs):
        employee, error = self._require_employee()
        if error:
            return error
        return self._json_response({"employee": self._employee_payload(employee), "attendance": self._status_payload(employee)})

    @http.route("/face_attendance/punch", type="http", auth="none", methods=["POST"], csrf=False)
    def punch(self, **kwargs):
        employee, error = self._require_employee()
        if error:
            return error
        body = self._body()
        accepted = bool(body.get("accepted"))
        match_score = float(body.get("match_score") or 0.0)
        threshold = float(body.get("threshold") or self._config("face_attendance.match_threshold", "0.82"))
        device_id = body.get("device_id")
        app_version = body.get("app_version")
        failure_reason = body.get("failure_reason")

        log = request.env["face.attendance.log"].sudo().create(
            {
                "employee_id": employee.id,
                "device_uid": device_id,
                "app_version": app_version,
                "match_score": match_score,
                "threshold": threshold,
                "accepted": accepted and match_score >= threshold,
                "failure_reason": failure_reason,
                "raw_payload": json.dumps(body),
            }
        )

        if not log.accepted:
            return self._json_response({"accepted": False, "log_id": log.id, "attendance": self._status_payload(employee)})

        open_attendance = request.env["hr.attendance"].sudo().search(
            [("employee_id", "=", employee.id), ("check_out", "=", False)],
            limit=1,
            order="check_in desc",
        )
        now = fields.Datetime.now()
        if open_attendance:
            open_attendance.write(
                {
                    "check_out": now,
                    "recognition_confidence": match_score,
                    "recognition_method": "face",
                    "face_device_uid": device_id,
                    "face_log_id": log.id,
                }
            )
            attendance = open_attendance
            punch_type = "check_out"
        else:
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
        log.write({"attendance_id": attendance.id, "punch_type": punch_type})
        return self._json_response(
            {
                "accepted": True,
                "punch_type": punch_type,
                "log_id": log.id,
                "attendance": self._status_payload(employee),
            }
        )

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

    def _config(self, key, default):
        return request.env["ir.config_parameter"].sudo().get_param(key, default)
