from odoo import fields, models


class HrAttendance(models.Model):
    _inherit = "hr.attendance"

    recognition_confidence = fields.Float()
    recognition_method = fields.Selection(
        [("face", "Face"), ("manual", "Manual"), ("offline", "Offline")],
        default="manual",
    )
    face_device_uid = fields.Char()
    face_log_id = fields.Many2one("face.attendance.log", ondelete="set null")
