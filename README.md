# FaceAttend

Shared-scanner face attendance system with Odoo as the attendance system of record, FastAPI/InsightFace as the face matching service, and a Flutter scanner app for attendance capture.

## Structure

- `face_attend_app/` - Flutter shared scanner app.
- `face_middleware/` - FastAPI face-recognition middleware using InsightFace, PostgreSQL, pgvector, and anti-spoofing.
- `face_attendance/` - Odoo addon for scanner setup, avatar-based face enrollment, audit logs, and `hr.attendance` integration.

## Middleware Setup

The middleware must run outside Odoo. It stores face embeddings in PostgreSQL with `pgvector`; raw employee photos stay in Odoo as employee avatars.

```bash
cd face_middleware
python3 -m venv .venv
. .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
uvicorn app.main:app --reload --host 0.0.0.0 --port 8019
```

Required production settings in `face_middleware/.env`:

```env
FACE_MIDDLEWARE_API_KEY=change-this
FACE_MIDDLEWARE_EMBEDDING_BACKEND=insightface
FACE_MIDDLEWARE_DATABASE_URL=postgresql://face_attend:face_attend@127.0.0.1:5433/face_attend
FACE_MIDDLEWARE_MATCH_THRESHOLD=0.70
FACE_MIDDLEWARE_ANTI_SPOOFING_ENABLED=true
FACE_MIDDLEWARE_ALLOW_ANTISPOOF_STUB=false
FACE_MIDDLEWARE_ANTISPOOF_MODEL_PATH=models/anti_spoofing/silent_face
```

PostgreSQL must have the `vector` extension available. The middleware creates its embedding tables and indexes on startup when the configured database user has permission.

## Odoo Setup

1. Copy or symlink `face_attendance` into an Odoo addons path.
2. Update the Odoo app list.
3. Install **Face Attendance**.
4. Assign HR/admin users to the HR Attendance and Face Attendance manager groups.
5. Open **Face Attendance > Configuration** and set:
   - middleware URL, for example `http://SERVER_IP:8019`
   - middleware API key matching `FACE_MIDDLEWARE_API_KEY`
   - confidence threshold, default `0.70`
   - liveness / anti-spoofing enabled
6. Create a scanner device in Odoo and generate/copy its setup code.
7. Add employees in Odoo and upload a real single-face employee avatar.
8. Save the employee or click **Sync Avatar To Middleware** to index the avatar embedding.

New employees are indexed automatically when a real avatar is saved. Placeholder initials or SVG avatars are rejected.

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
