import base64
import binascii

import requests

from odoo import _, api, fields, models
from odoo.exceptions import UserError


class HrEmployee(models.Model):
    _inherit = "hr.employee"

    face_registered = fields.Boolean(default=False)
    face_registered_date = fields.Datetime()
    face_enrollment_count = fields.Integer(default=0)
    face_sync_error = fields.Text(readonly=True)
    face_template_ids = fields.One2many("face.attendance.template", "employee_id")
    face_device_ids = fields.One2many("face.attendance.device", "employee_id")
    face_photo_ids = fields.One2many("face.attendance.photo", "employee_id", string="Legacy Face Photos")

    def _avatar_image_bytes(self):
        self.ensure_one()
        if not self.image_1920:
            raise UserError(_("Upload a real employee avatar before syncing face data."))
        try:
            image_bytes = base64.b64decode(self.image_1920)
        except (binascii.Error, TypeError, ValueError) as error:
            raise UserError(_("Upload a real employee avatar before syncing face data.")) from error

        stripped = image_bytes.lstrip().lower()
        if not image_bytes or stripped.startswith(b"<svg") or stripped.startswith(b"<?xml"):
            raise UserError(_("Upload a real employee avatar before syncing face data."))
        return image_bytes

    def _middleware_error_message(self, response):
        try:
            payload = response.json()
        except ValueError:
            return response.text or response.reason

        detail = payload.get("detail") if isinstance(payload, dict) else None
        if isinstance(detail, dict):
            message = detail.get("message") or detail.get("code")
            code = detail.get("code")
            if code and message and code != message:
                return "%s (%s)" % (message, code)
            if message:
                return message
        if isinstance(detail, str):
            return detail
        return response.text or response.reason

    @api.model_create_multi
    def create(self, vals_list):
        employees = super().create(vals_list)
        employees._auto_sync_face_to_middleware(vals_list)
        return employees

    def write(self, vals):
        result = super().write(vals)
        if {"image_1920", "name"} & set(vals):
            self._auto_sync_face_to_middleware([vals])
        return result

    def unlink(self):
        employee_ids = self.ids
        result = super().unlink()
        self._delete_faces_from_middleware(employee_ids)
        return result

    def _face_attendance_config(self):
        return self.env["face.attendance.config"].sudo().search([("active", "=", True)], limit=1)

    def _delete_faces_from_middleware(self, employee_ids):
        config = self._face_attendance_config()
        if not config or not config.middleware_url or not config.api_key:
            return
        for employee_id in employee_ids:
            try:
                requests.delete(
                    "%s/employee/%s" % (config.middleware_url.rstrip("/"), employee_id),
                    headers={"X-API-Key": config.api_key},
                    timeout=15,
                )
            except requests.RequestException:
                continue

    def _auto_sync_face_to_middleware(self, vals_list):
        if self.env.context.get("skip_face_auto_sync"):
            return

        avatar_changed = any("image_1920" in vals for vals in vals_list)
        name_changed = any("name" in vals for vals in vals_list)
        if not avatar_changed and not name_changed:
            return

        employees = self.filtered("image_1920")
        if name_changed and not avatar_changed:
            employees = employees.filtered("face_registered")
        for employee in employees:
            try:
                employee.with_context(skip_face_auto_sync=True).action_sync_face_to_middleware()
            except UserError as error:
                employee.with_context(skip_face_auto_sync=True).write(
                    {
                        "face_registered": False,
                        "face_registered_date": False,
                        "face_sync_error": str(error),
                    }
                )

    def action_reset_face_enrollment(self):
        for employee in self:
            employee.face_template_ids.write({"active": False})
            employee.write(
                {
                    "face_registered": False,
                    "face_registered_date": False,
                    "face_sync_error": False,
                }
            )
        return True

    def action_sync_face_to_middleware(self):
        config = self._face_attendance_config()
        if not config or not config.middleware_url or not config.api_key:
            raise UserError(_("Configure an active Face Attendance middleware URL and API key first."))

        for employee in self:
            image_bytes = employee._avatar_image_bytes()

            files = [
                (
                    "files",
                    (
                        "employee_%s_avatar.jpg" % employee.id,
                        image_bytes,
                        "image/jpeg",
                    ),
                )
            ]

            try:
                response = requests.post(
                    config.middleware_url.rstrip("/") + "/register",
                    headers={"X-API-Key": config.api_key},
                    data={"employee_id": str(employee.id), "employee_name": employee.name},
                    files=files,
                    timeout=60,
                )
                if not response.ok:
                    message = employee._middleware_error_message(response)
                    raise UserError(_("Middleware rejected %s: %s") % (employee.name, message))
                response_payload = response.json()
            except requests.RequestException as error:
                raise UserError(_("Middleware face sync failed for %s: %s") % (employee.name, error)) from error
            except ValueError as error:
                raise UserError(_("Middleware face sync failed for %s: invalid response") % employee.name) from error

            self.env["face.attendance.template"].sudo().search(
                [("employee_id", "=", employee.id), ("active", "=", True)]
            ).write({"active": False})
            self.env["face.attendance.template"].sudo().create(
                {
                    "employee_id": employee.id,
                    "embedding_json": "[]",
                    "model_version": "insightface-buffalo-l",
                    "device_uid": "odoo-admin-sync",
                    "quality_score": response_payload.get("detection_score") or 0.0,
                    "active": True,
                }
            )
            employee.with_context(skip_face_auto_sync=True).write(
                {
                    "face_registered": True,
                    "face_registered_date": fields.Datetime.now(),
                    "face_enrollment_count": employee.face_enrollment_count + 1,
                    "face_sync_error": False,
                }
            )

        return True
