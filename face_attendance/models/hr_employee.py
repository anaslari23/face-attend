import base64
import binascii

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

    @api.model_create_multi
    def create(self, vals_list):
        employees = super().create(vals_list)
        employees._auto_prepare_face_for_scanner(vals_list)
        return employees

    def write(self, vals):
        result = super().write(vals)
        if {"image_1920", "name"} & set(vals):
            self._auto_prepare_face_for_scanner([vals])
        if "active" in vals and not vals["active"]:
            templates = self.env["face.attendance.template"]
            for employee in self:
                templates.sudo().disable_for_employee(employee.id, employee.name)
        return result

    def unlink(self):
        templates = self.env["face.attendance.template"]
        for employee in self:
            templates.sudo().disable_for_employee(employee.id, employee.name)
        result = super().unlink()
        return result

    def _auto_prepare_face_for_scanner(self, vals_list):
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
                employee.with_context(skip_face_auto_sync=True).action_prepare_avatar_for_scanner()
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
            employee.write(
                {
                    "face_registered": False,
                    "face_registered_date": False,
                    "face_sync_error": False,
                }
            )
        return True

    def action_prepare_avatar_for_scanner(self):
        for employee in self:
            employee._avatar_image_bytes()

            employee.with_context(skip_face_auto_sync=True).write(
                {
                    "face_registered": False,
                    "face_registered_date": fields.Datetime.now(),
                    "face_enrollment_count": employee.face_enrollment_count + 1,
                    "face_sync_error": False,
                }
            )
            self.env["face.attendance.template"].sudo().mark_pending(employee, employee._avatar_image_bytes())

        return True

    def action_sync_face_to_middleware(self):
        return self.action_prepare_avatar_for_scanner()
