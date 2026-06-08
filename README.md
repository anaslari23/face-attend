# FaceAttend

Employee-phone face attendance system with Flutter on-device face flow and Odoo as the attendance system of record.

## Structure

- `face_attend_app/` - Flutter mobile app.
- `face_middleware/` - FastAPI face-recognition middleware.
- `face_attendance/` - Odoo addon for mobile API, enrollment records, audit logs, and `hr.attendance` integration.

## Middleware Setup

```bash
cd face_middleware
python3 -m venv .venv
. .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
uvicorn app.main:app --reload --host 0.0.0.0 --port 8019
```

For local API tests without InsightFace model setup:

```bash
FACE_MIDDLEWARE_EMBEDDING_BACKEND=dev uvicorn app.main:app --reload --port 8019
```

## Odoo Setup

1. Copy or symlink `face_attendance` into an Odoo addons path.
2. Update the Odoo app list.
3. Install **Face Attendance**.
4. Assign HR/admin users to **Face Attendance Manager**.
5. Ensure employees are linked to Odoo users through `hr.employee.user_id`; mobile login uses that relation.
6. Optional config parameters:
   - `face_attendance.match_threshold`, default `0.82`
   - `face_attendance.model_version`, default `mobilefacenet-v1`

## Flutter Setup

```bash
cd face_attend_app
flutter pub get
flutter run
```

The current face embedding service includes a deterministic development fallback so the app/API flow can be tested before adding a production TFLite model. Add the real model under `face_attend_app/assets/models/` and replace the fallback in `FaceRecognitionService` with model inference before production.

## Implemented API

- `POST /face_attendance/login`
- `POST /face_attendance/enroll`
- `GET /face_attendance/template`
- `GET /face_attendance/status`
- `POST /face_attendance/punch`

## Validation

```bash
cd face_attend_app
flutter analyze
flutter test
```
