import hashlib
import json
import os
import secrets
import struct
from datetime import timedelta

# pyrefly: ignore [missing-import]
from odoo import _, api, fields, models
# pyrefly: ignore [missing-import]
from odoo.exceptions import UserError

from ..services import embed_avatar


ARCFACE_MODEL_VERSION = "arcface-w600k-r50-align-v3"
EMBEDDING_DIMENSIONS = 512
EMBEDDING_BYTES = EMBEDDING_DIMENSIONS * 4


class FaceAttendanceIndexState(models.Model):
    _name = "face.attendance.index.state"
    _description = "Face Attendance Scanner Index State"

    name = fields.Char(required=True, default="default", readonly=True)
    revision = fields.Integer(default=0, required=True)

    _sql_constraints = [
        ("face_attendance_index_state_name_unique", "unique(name)", "Only one scanner index state is allowed."),
    ]

    @api.model
    def next_revision(self):
        state = self.search([("name", "=", "default")], limit=1)
        if not state:
            state = self.create({"name": "default"})
        self.env.cr.execute(
            "SELECT id FROM face_attendance_index_state WHERE id = %s FOR UPDATE",
            [state.id],
        )
        state.revision += 1
        return state.revision


class FaceAttendanceTemplate(models.Model):
    _name = "face.attendance.template"
    _description = "Face Attendance Template"
    _order = "revision desc, id desc"

    employee_id = fields.Many2one("hr.employee", index=True, ondelete="set null")
    employee_odoo_id = fields.Integer(index=True, copy=False)
    employee_name = fields.Char(copy=False)
    embedding_json = fields.Text(copy=False)  # Legacy field retained for upgrade compatibility; never populated.
    embedding_ciphertext = fields.Text(copy=False)
    embedding_dimensions = fields.Integer(default=EMBEDDING_DIMENSIONS, required=True)
    avatar_hash = fields.Char(index=True, copy=False)
    model_version = fields.Char(required=True, default=ARCFACE_MODEL_VERSION, index=True)
    revision = fields.Integer(required=True, default=0, index=True, copy=False)
    state = fields.Selection(
        [("pending", "Pending"), ("ready", "Ready"), ("failed", "Failed"), ("disabled", "Disabled")],
        default="pending",
        required=True,
        index=True,
    )
    worker_error = fields.Text(readonly=True, copy=False)
    device_uid = fields.Char(index=True)  # Legacy field retained for existing records.
    quality_score = fields.Float()
    active = fields.Boolean(default=True, index=True)

    def name_get(self):
        return [(record.id, "%s - %s" % (record.employee_name, record.model_version)) for record in self]

    @api.model
    def _next_revision(self):
        return self.env["face.attendance.index.state"].sudo().next_revision()

    @api.model
    def _template_key(self):
        key = os.environ.get("FACE_ATTENDANCE_TEMPLATE_KEY") or self.env["ir.config_parameter"].sudo().get_param(
            "face_attendance.template_key"
        )
        if not key:
            raise UserError(_("Set FACE_ATTENDANCE_TEMPLATE_KEY before generating face templates."))
        try:
            from cryptography.fernet import Fernet

            return Fernet(key.encode())
        except Exception as error:
            raise UserError(_("FACE_ATTENDANCE_TEMPLATE_KEY must be a valid Fernet key.")) from error

    @api.model
    def _avatar_hash(self, image_bytes):
        return hashlib.sha256(image_bytes).hexdigest()

    @api.model
    def mark_pending(self, employee, image_bytes):
        values = {
            "employee_id": employee.id,
            "employee_odoo_id": employee.id,
            "employee_name": employee.name,
            "avatar_hash": self._avatar_hash(image_bytes),
            "model_version": ARCFACE_MODEL_VERSION,
            "revision": self._next_revision(),
            "state": "pending",
            "worker_error": False,
            "active": True,
            "embedding_ciphertext": False,
            "embedding_json": False,
        }
        template = self.search([("employee_odoo_id", "=", employee.id)], limit=1)
        if template:
            template.write(values)
        else:
            template = self.create(values)
        return template

    def disable_for_employee(self, employee_id, employee_name="Deleted employee"):
        template = self.search([("employee_odoo_id", "=", employee_id)], limit=1)
        if template:
            template.write(
                {
                    "employee_id": False,
                    "employee_name": employee_name,
                    "active": False,
                    "state": "disabled",
                    "revision": self._next_revision(),
                    "embedding_ciphertext": False,
                }
            )

    @api.model
    def queue_active_employee_backfill(self):
        """Queue only avatars without a current central template."""
        queued = 0
        employees = self.env["hr.employee"].sudo().search([("active", "=", True), ("image_1920", "!=", False)])
        for employee in employees:
            try:
                image_bytes = employee._avatar_image_bytes()
            except UserError:
                continue
            template = self.search([("employee_odoo_id", "=", employee.id)], limit=1)
            if (
                template
                and template.active
                and template.state == "ready"
                and template.model_version == ARCFACE_MODEL_VERSION
                and template.avatar_hash == self._avatar_hash(image_bytes)
            ):
                continue
            self.mark_pending(employee, image_bytes)
            queued += 1
        return queued

    @api.model
    def retry_failed_templates(self):
        queued = 0
        for template in self.search([("state", "=", "failed"), ("active", "=", True)]):
            employee = template.employee_id
            if not employee or not employee.active:
                continue
            try:
                self.mark_pending(employee, employee._avatar_image_bytes())
                queued += 1
            except UserError:
                continue
        return queued

    def _set_embedding(self, embedding_bytes, quality_score=0.0):
        if len(embedding_bytes) != EMBEDDING_BYTES:
            raise UserError(_("The template worker must return exactly 512 float32 values."))
        # Validate the worker payload before accepting it; packed network vectors are big-endian float32.
        struct.unpack("!%sf" % EMBEDDING_DIMENSIONS, embedding_bytes)
        for template in self:
            template.write(
                {
                    "embedding_ciphertext": self._template_key().encrypt(embedding_bytes).decode(),
                    "embedding_dimensions": EMBEDDING_DIMENSIONS,
                    "quality_score": quality_score,
                    "state": "ready",
                    "worker_error": False,
                    "active": True,
                    "revision": self._next_revision(),
                }
            )
            if template.employee_id:
                template.employee_id.with_context(skip_face_auto_sync=True).write(
                    {"face_registered": True, "face_registered_date": fields.Datetime.now(), "face_sync_error": False}
                )

    def embedding_bytes(self):
        self.ensure_one()
        if not self.embedding_ciphertext or self.state != "ready" or not self.active:
            raise UserError(_("This employee does not have a ready scanner template."))
        try:
            return self._template_key().decrypt(self.embedding_ciphertext.encode())
        except Exception as error:
            raise UserError(_("Could not decrypt the employee scanner template.")) from error

    @api.model
    def _cron_generate_templates(self, limit=50):
        pending = self.search([("state", "=", "pending"), ("active", "=", True)], limit=limit, order="revision")
        for template in pending:
            employee = template.employee_id
            if not employee or not employee.active or not employee.image_1920:
                template.disable_for_employee(template.employee_odoo_id)
                continue
            try:
                image_bytes = employee._avatar_image_bytes()
                if self._avatar_hash(image_bytes) != template.avatar_hash:
                    self.mark_pending(employee, image_bytes)
                    continue
                embedding, quality_score, avatar_hash = embed_avatar(self.env, image_bytes)
                if avatar_hash != template.avatar_hash:
                    raise UserError(_("ArcFace worker returned a different avatar hash."))
                template._set_embedding(embedding, quality_score)
            except Exception as error:
                template.write({"state": "failed", "worker_error": str(error), "revision": self._next_revision()})
                if template.employee_id:
                    template.employee_id.with_context(skip_face_auto_sync=True).write(
                        {"face_registered": False, "face_sync_error": str(error)}
                    )


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
    template_pending_count = fields.Integer(compute="_compute_template_counts")
    template_ready_count = fields.Integer(compute="_compute_template_counts")
    template_failed_count = fields.Integer(compute="_compute_template_counts")

    def _compute_template_counts(self):
        templates = self.env["face.attendance.template"].sudo()
        counts = {
            state: templates.search_count([("state", "=", state), ("active", "=", True)])
            for state in ("pending", "ready", "failed")
        }
        for config in self:
            config.template_pending_count = counts["pending"]
            config.template_ready_count = counts["ready"]
            config.template_failed_count = counts["failed"]

    def action_open_logs(self):
        self.ensure_one()
        return {"type": "ir.actions.act_window", "name": "Face Attendance Logs", "res_model": "face.attendance.log", "view_mode": "list,form,pivot,graph"}

    def action_queue_template_backfill(self):
        self.ensure_one()
        queued = self.env["face.attendance.template"].sudo().queue_active_employee_backfill()
        return {
            "type": "ir.actions.client",
            "tag": "display_notification",
            "params": {
                "title": _("Face template backfill queued"),
                "message": _("%(count)s employee avatars are queued for the template worker.") % {"count": queued},
                "type": "success",
                "sticky": False,
            },
        }

    def action_retry_failed_templates(self):
        self.ensure_one()
        queued = self.env["face.attendance.template"].sudo().retry_failed_templates()
        return {
            "type": "ir.actions.client",
            "tag": "display_notification",
            "params": {
                "title": _("Failed templates queued"),
                "message": _("%(count)s failed templates are queued for retry.") % {"count": queued},
                "type": "success",
                "sticky": False,
            },
        }


class FaceAttendanceConnectedDevice(models.Model):
    _name = "face.attendance.connected.device"
    _description = "Face Attendance Connected Device"

    name = fields.Char(string="Device ID", required=True)
    generated_device_id = fields.Char(string="Generated Device ID", readonly=True)
    device_id = fields.Many2one("face.attendance.device", string="Scanner Setup", ondelete="cascade", required=True)

    _sql_constraints = [
        ("device_unique", "unique(name, device_id)", "Device must be unique per scanner setup.")
    ]

class FaceAttendanceDevice(models.Model):
    _name = "face.attendance.device"
    _description = "Face Attendance Device"
    _order = "last_seen_at desc, create_date desc"

    def _default_token(self):
        return secrets.token_urlsafe(48)

    def _default_token_expires_at(self):
        return fields.Datetime.now() + timedelta(days=365)

    name = fields.Char(required=True)
    device_type = fields.Selection([("scanner", "Shared Scanner"), ("employee", "Employee Device")], required=True, default="scanner", index=True)
    employee_id = fields.Many2one("hr.employee", index=True, ondelete="cascade")
    device_uid = fields.Char(required=True, index=True)
    token = fields.Char(required=True, index=True, copy=False, default=_default_token)
    setup_code = fields.Char(string="Scanner Setup Code", compute="_compute_setup_code")
    token_expires_at = fields.Datetime(required=True, default=_default_token_expires_at)
    last_seen_at = fields.Datetime()
    active = fields.Boolean(default=True)
    config_id = fields.Many2one("face.attendance.config", string="Configuration",
                                default=lambda self: self.env["face.attendance.config"].search([], limit=1))

    devices_can_connect = fields.Integer(string="Devices Can Connect", default=1)
    total_connected_devices = fields.Integer(string="Total Connected Devices", compute="_compute_total_connected_devices", store=True)
    connected_device_line_ids = fields.One2many("face.attendance.connected.device", "device_id", string="Connected Device IDs")
    device_try_to_connect = fields.Char(string="Device Trying to Connect")

    _sql_constraints = [("employee_device_unique", "unique(employee_id, device_uid)", "This device is already registered for the employee.")]

    @api.depends("connected_device_line_ids")
    def _compute_total_connected_devices(self):
        for record in self:
            record.total_connected_devices = len(record.connected_device_line_ids)

    @api.constrains("devices_can_connect", "connected_device_line_ids")
    def _check_devices_can_connect(self):
        for record in self:
            if record.devices_can_connect < len(record.connected_device_line_ids):
                raise UserError(_("Devices Can Connect cannot be less than the Total Connected Devices."))

    @api.onchange("devices_can_connect", "connected_device_line_ids")
    def _onchange_devices_can_connect(self):
        if self.devices_can_connect < len(self.connected_device_line_ids):
            return {
                "warning": {
                    "title": _("Warning"),
                    "message": _("Devices Can Connect cannot be less than the Total Connected Devices. Please increase the limit or remove some connected devices.")
                }
            }

    @api.constrains("device_type", "employee_id")
    def _check_employee_device(self):
        for record in self:
            if record.device_type == "employee" and (not record.employee_id or not record.device_uid):
                raise UserError(_("Employee devices must be linked to an employee and have a Device UID."))

    def action_generate_token(self):
        for record in self:
            record.token = secrets.token_urlsafe(48)

    def _compute_setup_code(self):
        for record in self:
            record.setup_code = record.token


class FaceAttendanceLog(models.Model):
    _name = "face.attendance.log"
    _description = "Face Attendance Audit Log"
    _order = "punch_time desc"

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
    accepted = fields.Boolean(default=True, index=True)
    failure_reason = fields.Char()
    raw_payload = fields.Text()
    is_sync = fields.Boolean(string="SYNC", default=False, index=True)

    punch_time = fields.Datetime(string="Punch Time", default=fields.Datetime.now, index=True)

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
        for vals in vals_list:
            if not vals.get("punch_time") and vals.get("create_date"):
                vals["punch_time"] = vals["create_date"]

        logs = super().create(vals_list)
        for log in logs.filtered(lambda item: item.employee_id and item.accepted):
            open_attendance = self.env["hr.attendance"].search(
                [("employee_id", "=", log.employee_id.id), ("check_out", "=", False)], limit=1, order="check_in desc"
            )
            if open_attendance:
                open_attendance.write({"check_out": log.punch_time, "out_mode": "pi_smart_punch"})
                log.write({"attendance_id": open_attendance.id, "punch_type": "check_out"})
            else:
                attendance = self.env["hr.attendance"].create(
                    {"employee_id": log.employee_id.id, "check_in": log.punch_time, "recognition_confidence": log.match_score, "recognition_method": "face", "face_device_uid": log.device_uid, "face_log_id": log.id, "in_mode": "pi_smart_punch"}
                )
                log.write({"attendance_id": attendance.id, "punch_type": "check_in"})
        return logs

    @api.model
    def _cron_auto_checkout(self):
        # Explicit missed-checkout policy, scheduled once late in the day by data/ir_cron.xml.
        now = fields.Datetime.now()
        open_attendances = self.env["hr.attendance"].search([("check_out", "=", False), ("check_in", "<", now.replace(hour=0, minute=0, second=0, microsecond=0))])
        for attendance in open_attendances:
            attendance.write({"check_out": now.replace(hour=23, minute=59, second=59, microsecond=0), "out_mode": "pi_smart_punch"})
