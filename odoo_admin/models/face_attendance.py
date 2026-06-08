from odoo import api, fields, models


class FaceAttendanceTemplate(models.Model):
    _name = "face.attendance.template"
    _description = "Face Attendance Template"
    _order = "create_date desc"

    employee_id = fields.Many2one("hr.employee", required=True, index=True, ondelete="cascade")
    embedding_json = fields.Text(required=True)
    model_version = fields.Char(required=True, default="mobilefacenet-v1")
    device_uid = fields.Char(index=True)
    quality_score = fields.Float()
    active = fields.Boolean(default=True, index=True)

    def name_get(self):
        return [(record.id, "%s - %s" % (record.employee_id.name, record.model_version)) for record in self]


class FaceAttendanceConfig(models.Model):
    _name = "face.attendance.config"
    _description = "Face Attendance Configuration"
    _rec_name = "name"

    name = fields.Char(required=True, default="Default Face Attendance")
    middleware_url = fields.Char(required=True, default="http://127.0.0.1:8019")
    api_key = fields.Char(copy=False)
    confidence_threshold = fields.Float(default=0.45)
    liveness_required = fields.Boolean(default=True)
    anti_spoofing_required = fields.Boolean(default=False)
    active = fields.Boolean(default=True)
    notes = fields.Text()

    def action_open_logs(self):
        self.ensure_one()
        return {
            "type": "ir.actions.act_window",
            "name": "Face Attendance Logs",
            "res_model": "face.attendance.log",
            "view_mode": "list,form,pivot,graph",
        }


class FaceAttendanceDevice(models.Model):
    _name = "face.attendance.device"
    _description = "Face Attendance Mobile Device"
    _order = "last_seen_at desc, create_date desc"

    name = fields.Char(required=True)
    employee_id = fields.Many2one("hr.employee", required=True, index=True, ondelete="cascade")
    device_uid = fields.Char(required=True, index=True)
    token = fields.Char(required=True, index=True, copy=False)
    token_expires_at = fields.Datetime(required=True)
    last_seen_at = fields.Datetime()
    active = fields.Boolean(default=True)

    _sql_constraints = [
        ("employee_device_unique", "unique(employee_id, device_uid)", "This device is already registered for the employee."),
    ]


class FaceAttendanceLog(models.Model):
    _name = "face.attendance.log"
    _description = "Face Attendance Audit Log"
    _order = "create_date desc"

    employee_id = fields.Many2one("hr.employee", required=True, index=True, ondelete="cascade")
    attendance_id = fields.Many2one("hr.attendance", index=True, ondelete="set null")
    device_uid = fields.Char(index=True)
    app_version = fields.Char()
    punch_type = fields.Selection([("check_in", "Check In"), ("check_out", "Check Out")])
    match_score = fields.Float(required=True)
    threshold = fields.Float(required=True)
    accepted = fields.Boolean(default=False, index=True)
    failure_reason = fields.Char()
    raw_payload = fields.Text()

    result_label = fields.Char(compute="_compute_result_label")

    @api.depends("accepted", "failure_reason")
    def _compute_result_label(self):
        for record in self:
            record.result_label = "Accepted" if record.accepted else record.failure_reason or "Rejected"
