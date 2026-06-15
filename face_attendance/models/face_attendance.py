import secrets
from datetime import timedelta

# pyrefly: ignore [missing-import]
from odoo import _, api, fields, models
# pyrefly: ignore [missing-import]
from odoo.exceptions import UserError


class FaceAttendanceTemplate(models.Model):
    _name = "face.attendance.template"
    _description = "Face Attendance Template"
    _order = "create_date desc"

    employee_id = fields.Many2one("hr.employee", required=True, index=True, ondelete="cascade")
    embedding_json = fields.Text(required=True)
    model_version = fields.Char(required=True, default="arcface-w600k-r50-align-v3")
    device_uid = fields.Char(index=True)
    quality_score = fields.Float()
    active = fields.Boolean(default=True, index=True)

    def name_get(self):
        return [(record.id, "%s - %s" % (record.employee_id.name, record.model_version)) for record in self]

    def init(self):
        self.env.cr.execute("DELETE FROM face_attendance_template")


class FaceAttendancePhoto(models.Model):
    _name = "face.attendance.photo"
    _description = "Employee Face Attendance Photo"
    _order = "sequence, id"

    employee_id = fields.Many2one("hr.employee", required=True, index=True, ondelete="cascade")
    name = fields.Char(required=True, default="Face Photo")
    sequence = fields.Integer(default=10)
    image_1920 = fields.Image(required=True, max_width=1920, max_height=1920)
    active = fields.Boolean(default=True)


class FaceAttendanceConfig(models.Model):
    _name = "face.attendance.config"
    _description = "Face Attendance Configuration"
    _rec_name = "name"

    name = fields.Char(required=True, default="Default Face Attendance")
    confidence_threshold = fields.Float(default=0.70)
    liveness_required = fields.Boolean(default=True)
    anti_spoofing_required = fields.Boolean(default=True)
    active = fields.Boolean(default=True)
    device_ids = fields.One2many("face.attendance.device", "config_id", string="Registered Devices")

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
    _description = "Face Attendance Device"
    _order = "last_seen_at desc, create_date desc"

    def _default_token(self):
        return secrets.token_urlsafe(48)

    def _default_token_expires_at(self):
        return fields.Datetime.now() + timedelta(days=365)

    name = fields.Char(required=True)
    device_type = fields.Selection(
        [("scanner", "Shared Scanner"), ("employee", "Employee Device")],
        required=True,
        default="scanner",
        index=True,
    )
    employee_id = fields.Many2one("hr.employee", index=True, ondelete="cascade")
    device_uid = fields.Char(required=True, index=True)
    token = fields.Char(required=True, index=True, copy=False, default=_default_token)
    setup_code = fields.Char(string="Scanner Setup Code", compute="_compute_setup_code")
    token_expires_at = fields.Datetime(required=True, default=_default_token_expires_at)
    last_seen_at = fields.Datetime()
    active = fields.Boolean(default=True)
    config_id = fields.Many2one("face.attendance.config", string="Configuration", default=lambda self: self.env["face.attendance.config"].search([], limit=1))

    _sql_constraints = [
        ("employee_device_unique", "unique(employee_id, device_uid)", "This device is already registered for the employee."),
    ]

    @api.constrains("device_type", "employee_id")
    def _check_employee_device(self):
        for record in self:
            if record.device_type == "employee" and not record.employee_id:
                raise UserError(_("Employee devices must be linked to an employee."))

    def action_generate_token(self):
        for record in self:
            record.token = secrets.token_urlsafe(48)

    def _compute_setup_code(self):
        for record in self:
            record.setup_code = record.token


class FaceAttendanceLog(models.Model):
    _name = "face.attendance.log"
    _description = "Face Attendance Audit Log"
    _order = "create_date desc"

    employee_id = fields.Many2one("hr.employee", index=True, ondelete="cascade")
    attendance_id = fields.Many2one("hr.attendance", index=True, ondelete="set null")
    device_uid = fields.Char(index=True)
    app_version = fields.Char()
    punch_type = fields.Selection([("check_in", "In"), ("check_out", "Out")])
    match_score = fields.Float(required=True)
    threshold = fields.Float(required=True)
    second_best_confidence = fields.Float()
    embedding_source = fields.Char()
    review_embedding_id = fields.Integer()
    needs_review = fields.Boolean(default=False, index=True)
    liveness_passed = fields.Boolean(default=False, index=True)
    liveness_score = fields.Float()
    spoof_score = fields.Float()
    accepted = fields.Boolean(default=False, index=True)
    failure_reason = fields.Char()
    raw_payload = fields.Text()

    employee_odoo_id = fields.Integer(string="Employee ID", compute="_compute_employee_display", store=True)
    employee_name = fields.Char(string="Employee Name", compute="_compute_employee_display", store=True)
    result_label = fields.Char(compute="_compute_result_label")

    @api.depends("employee_id", "employee_id.name")
    def _compute_employee_display(self):
        for record in self:
            record.employee_odoo_id = record.employee_id.id if record.employee_id else False
            record.employee_name = record.employee_id.name if record.employee_id else False

    @api.depends("accepted", "failure_reason")
    def _compute_result_label(self):
        for record in self:
            record.result_label = "Accepted" if record.accepted else record.failure_reason or "Rejected"

    @api.model_create_multi
    def create(self, vals_list):
        logs = super().create(vals_list)
        for log in logs:
            if log.employee_id and log.accepted:
                start_of_day = log.create_date.replace(hour=0, minute=0, second=0, microsecond=0)
                end_of_day = log.create_date.replace(hour=23, minute=59, second=59, microsecond=999999)
                
                last_log = self.env["face.attendance.log"].search([
                    ("employee_id", "=", log.employee_id.id),
                    ("create_date", ">=", start_of_day),
                    ("create_date", "<=", end_of_day),
                    ("id", "!=", log.id),
                    ("punch_type", "!=", False)
                ], limit=1, order="create_date desc")
                
                if not last_log:
                    punch_type = "check_in"
                elif last_log.punch_type == "check_in":
                    punch_type = "check_out"
                else:
                    punch_type = "check_in"

                daily_attendance = self.env["hr.attendance"].search([
                    ("employee_id", "=", log.employee_id.id),
                    ("check_in", ">=", start_of_day),
                    ("check_in", "<=", end_of_day)
                ], limit=1, order="check_in asc")
                
                if not daily_attendance:
                    daily_attendance = self.env["hr.attendance"].create({
                        "employee_id": log.employee_id.id,
                        "check_in": log.create_date,
                        "recognition_confidence": log.match_score,
                        "recognition_method": "face",
                        "face_device_uid": log.device_uid,
                        "face_log_id": log.id,
                    })
                
                log.attendance_id = daily_attendance.id if daily_attendance else False
                log.punch_type = punch_type
        return logs

    @api.model
    def _cron_auto_checkout(self):
        today = fields.Datetime.now()
        start_of_day = today.replace(hour=0, minute=0, second=0, microsecond=0)
        end_of_day = today.replace(hour=23, minute=59, second=59, microsecond=999999)
        
        domain = [
            ("check_in", ">=", start_of_day),
            ("check_in", "<=", end_of_day),
            ("check_out", "=", False),
        ]
        open_attendances = self.env["hr.attendance"].search(domain)
        
        for attendance in open_attendances:
            log_domain = [
                ("employee_id", "=", attendance.employee_id.id),
                ("accepted", "=", True),
                ("create_date", ">=", start_of_day),
                ("create_date", "<=", end_of_day),
            ]
            last_log = self.search(log_domain, order="create_date desc", limit=1)
            
            if last_log:
                attendance.write({"check_out": last_log.create_date})

