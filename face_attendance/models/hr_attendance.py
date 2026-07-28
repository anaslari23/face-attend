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

    in_mode = fields.Selection(selection_add=[
            ('pi_smart_punch', 'Pi Smart Punch')
    ])
    out_mode = fields.Selection(selection_add=[
        ('pi_smart_punch', 'Pi Smart Punch')
    ])
