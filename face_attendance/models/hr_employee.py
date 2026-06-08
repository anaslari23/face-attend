from odoo import fields, models


class HrEmployee(models.Model):
    _inherit = "hr.employee"

    face_registered = fields.Boolean(default=False)
    face_registered_date = fields.Datetime()
    face_enrollment_count = fields.Integer(default=0)
    face_template_ids = fields.One2many("face.attendance.template", "employee_id")
    face_device_ids = fields.One2many("face.attendance.device", "employee_id")

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
