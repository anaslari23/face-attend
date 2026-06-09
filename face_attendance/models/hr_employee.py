import base64

import requests

from odoo import _, fields, models
from odoo.exceptions import UserError


class HrEmployee(models.Model):
    _inherit = "hr.employee"

    face_registered = fields.Boolean(default=False)
    face_registered_date = fields.Datetime()
    face_enrollment_count = fields.Integer(default=0)
    face_template_ids = fields.One2many("face.attendance.template", "employee_id")
    face_device_ids = fields.One2many("face.attendance.device", "employee_id")
    face_photo_ids = fields.One2many("face.attendance.photo", "employee_id", string="Legacy Face Photos")

    def action_reset_face_enrollment(self):
        for employee in self:
            employee.face_template_ids.write({"active": False})
            employee.write(
                {
                    "face_registered": False,
                    "face_registered_date": False,
                }
            )
        return True

    def action_sync_face_to_middleware(self):
        config = self.env["face.attendance.config"].sudo().search([("active", "=", True)], limit=1)
        if not config or not config.middleware_url or not config.api_key:
            raise UserError(_("Configure an active Face Attendance middleware URL and API key first."))

        for employee in self:
            if not employee.image_1920:
                raise UserError(_("Upload an employee avatar before syncing face data."))

            files = [
                (
                    "files",
                    (
                        "employee_%s_avatar.jpg" % employee.id,
                        base64.b64decode(employee.image_1920),
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
                response.raise_for_status()
            except requests.RequestException as error:
                raise UserError(_("Middleware face sync failed for %s: %s") % (employee.name, error)) from error

            self.env["face.attendance.template"].sudo().search(
                [("employee_id", "=", employee.id), ("active", "=", True)]
            ).write({"active": False})
            self.env["face.attendance.template"].sudo().create(
                {
                    "employee_id": employee.id,
                    "embedding_json": "[]",
                    "model_version": "insightface-buffalo-l",
                    "device_uid": "odoo-admin-sync",
                    "quality_score": 1.0,
                    "active": True,
                }
            )
            employee.write(
                {
                    "face_registered": True,
                    "face_registered_date": fields.Datetime.now(),
                    "face_enrollment_count": employee.face_enrollment_count + 1,
                }
            )

        return True
