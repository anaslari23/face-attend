# FaceAttend

Shared-scanner face attendance system with Odoo as the attendance system of record, FastAPI/InsightFace as the face matching service, and a Flutter scanner app for attendance capture.

## Structure

- `face_attend_app/` - Flutter shared scanner app.
- `face_middleware/` - FastAPI face-recognition middleware using InsightFace, PostgreSQL, pgvector, and anti-spoofing.
- `face_attendance/` - Odoo addon for scanner setup, avatar-based face enrollment, audit logs, and `hr.attendance` integration.

## Middleware Setup

The middleware must run outside Odoo. It stores face embeddings in PostgreSQL with `pgvector`; raw employee photos stay in Odoo as employee avatars.

The middleware is not tied to one Odoo database. It indexes the employee IDs and names sent by whichever Odoo database is configured to use it. For clean production isolation, use one middleware database per Odoo database or tenant.

### 1. Prepare PostgreSQL + pgvector

Create a PostgreSQL database for middleware embeddings and enable `pgvector`:

```sql
CREATE USER face_attend WITH PASSWORD 'face_attend';
CREATE DATABASE face_attend OWNER face_attend;
\c face_attend
CREATE EXTENSION IF NOT EXISTS vector;
```

The PostgreSQL host can be local or remote. The middleware only needs a valid `FACE_MIDDLEWARE_DATABASE_URL`.

### 2. Install Python dependencies

```bash
cd face_middleware
python3 -m venv .venv
. .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
```

### 3. Configure middleware `.env`

Edit `face_middleware/.env`:

```env
FACE_MIDDLEWARE_API_KEY=change-this
FACE_MIDDLEWARE_EMBEDDING_BACKEND=insightface
FACE_MIDDLEWARE_DATABASE_URL=postgresql://face_attend:face_attend@127.0.0.1:5432/face_attend
FACE_MIDDLEWARE_MATCH_THRESHOLD=0.70
FACE_MIDDLEWARE_ANTI_SPOOFING_ENABLED=true
FACE_MIDDLEWARE_ALLOW_ANTISPOOF_STUB=false
FACE_MIDDLEWARE_ANTISPOOF_MODEL_PATH=models/anti_spoofing/silent_face
```

Use a strong private API key in production. The same key must be saved in Odoo Face Attendance configuration.

### 4. Start middleware

```bash
cd face_middleware
. .venv/bin/activate
uvicorn app.main:app --host 0.0.0.0 --port 8019
```

For production, run it under a process manager such as `systemd`, Supervisor, Docker, or another service runner. The scanner device must be able to reach this host/port.

Validate:

```bash
curl http://MIDDLEWARE_HOST:8019/health
```

Expected production health should show:

- `model_loaded: true`
- `database_connected: true`
- `antispoofing: ready`
- `antispoofing_model_loaded: true`

## Odoo Setup

The Odoo addon is standalone. It does not depend on this repository's local Odoo database. It can be installed in any Odoo 19 database as long as `hr` and `hr_attendance` are available.

### 1. Add the addon to any Odoo 19 instance

Copy `face_attendance/` into one of the target Odoo server's `addons_path` folders, or add the folder path to `addons_path`.

Example:

```ini
addons_path = /opt/odoo/odoo/addons,/opt/odoo/custom-addons
```

Then restart Odoo, update the Apps list, and install **Face Attendance** in the target database.

CLI install example:

```bash
./odoo-bin -c /path/to/odoo.conf -d TARGET_DATABASE -i face_attendance --stop-after-init
```

Upgrade after code changes:

```bash
./odoo-bin -c /path/to/odoo.conf -d TARGET_DATABASE -u face_attendance --stop-after-init
```

### 2. Configure Odoo users and menus

Assign HR/admin users to:

- `Officer: Manage all employees`
- `Officer: Manage attendances`
- `Officer: Manage all attendances`
- `Face Attendance User`
- `Face Attendance Manager`

These groups make **Employees**, **Attendances**, and **Face Attendance** menus visible.

### 3. Connect that Odoo database to middleware

In the target Odoo database:

1. Open **Face Attendance > Configuration**.
2. Create or edit the active configuration.
3. Set:
   - Middleware URL: `http://MIDDLEWARE_HOST:8019`
   - API key: same value as `FACE_MIDDLEWARE_API_KEY`
   - Confidence threshold: `0.70`
   - Liveness required: enabled
   - Anti-spoofing required: enabled

Each Odoo database can point to its own middleware instance/database. If multiple Odoo databases share one middleware database, employee IDs can overlap, so use separate middleware databases unless you intentionally manage multi-tenant isolation.

### 4. Create scanner device setup

In **Face Attendance > Devices**:

1. Create a device.
2. Set device type to **Shared Scanner**.
3. Save it.
4. Generate/copy the scanner setup code.
5. Enter that setup code in the Flutter scanner app.

The setup endpoint returns the scanner token and middleware details to the app. If Odoo stores middleware as `127.0.0.1`, the API converts it to the request host so a phone using the Odoo server IP can receive a reachable middleware URL.

### 5. Index employees from that Odoo database

For each employee in the target Odoo database:

1. Upload a real single-face employee avatar.
2. Save the employee.
3. Odoo automatically sends the avatar to middleware `/register`.
4. Confirm `Face Registered` is checked on the employee.

Manual fallback:

1. Open the employee.
2. Go to the **Face Attendance** tab.
3. Click **Sync Avatar To Middleware**.

The middleware stores only the generated embedding. The raw avatar remains in Odoo.

New employees are indexed automatically when a real avatar is saved. Placeholder initials or SVG avatars are rejected.

If you move the addon to another Odoo database, you must sync that database's employees to middleware. Existing embeddings from a different database should not be reused unless employee IDs and employee identities are intentionally the same.

## Flutter Setup

```bash
cd face_attend_app
flutter pub get
flutter run
```

The Flutter app is a shared scanner. It is configured once with the Odoo URL, database, scanner setup code, and middleware details returned by Odoo. Employees do not log in to the app and do not manually register their faces on the device.

Face recognition runs through the FastAPI middleware. The Flutter app performs lightweight on-device face detection/quality validation, uploads one captured image to middleware `/match`, then calls Odoo `/face_attendance/punch` only after a successful match.

## Implemented API

- `POST /face_attendance/scanner/setup`
- `GET /face_attendance/status`
- `POST /face_attendance/punch`
- `POST /register`
- `POST /match`
- `POST /match/faces`
- `GET /health`

## Deployment Bundle

For sharing with another Odoo/server environment, create or use:

- `face_attend_odoo_deploy_bundle.zip` - combined Odoo addon and middleware source package.
- `face_attendance_standalone.zip` - Odoo addon only.
- `face_middleware_standalone.zip` - FastAPI middleware only.

The combined bundle is enough for a technical deployment handoff, but it is not a one-click production installer. The target environment still needs:

- Odoo 19 with `hr` and `hr_attendance`
- Python runtime for middleware
- PostgreSQL with `pgvector`
- production `.env`
- reachable middleware host/IP from scanner devices
- HTTPS or reverse proxy for non-LAN deployments
- Flutter scanner APK or installed app

Recommended deployment layout:

```text
server/
  odoo/
    custom-addons/
      face_attendance/
  face_middleware/
    app/
    models/
    requirements.txt
    .env
```

Production checklist:

- Install Odoo addon in the target database.
- Start middleware and verify `/health`.
- Configure Odoo middleware URL/API key.
- Create scanner device and setup code.
- Upload employee avatars.
- Sync/index employees.
- Configure scanner app using Odoo URL, database, and setup code.
- Test real face, unknown face, and photo/screen spoof attempts.

## Validation

```bash
cd face_attend_app
flutter analyze
flutter test
```

Middleware validation:

```bash
curl http://localhost:8019/health
```

Expected production health should show model loaded, database connected, and anti-spoofing ready.
