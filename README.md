# FaceAttend

Phone-only shared-scanner face attendance for Odoo.

Odoo is the system of record for employees, encrypted face templates, scanner devices, attendance records, and audit logs. The Flutter scanner app runs face detection and ArcFace matching locally on the phone, then sends only the attendance result back to Odoo.

There is no FastAPI middleware, PostgreSQL, or pgvector requirement in the active deployment flow.

## Structure

- `face_attendance/` - standalone Odoo addon for scanner setup, employee avatar sync, audit logs, and `hr.attendance` integration.
- `face_attend_app/` - Flutter shared scanner app with on-device MediaPipe-style face detection and ArcFace `w600k_r50.onnx` embeddings.

## Runtime Flow

1. HR/admin creates employees in Odoo and uploads a real single-face employee avatar.
2. Odoo's template worker generates and encrypts a 512-d ArcFace embedding once per new or changed avatar.
3. The scanner phone loads its verified local index immediately, then downloads only changed binary vectors through `/face_attendance/scanner/index/*`.
4. During attendance scan, the phone detects exactly one face, creates a live ArcFace embedding, and matches locally.
5. If the match passes threshold and ambiguity checks, the phone calls `/face_attendance/punch`.
6. Odoo creates or updates `hr.attendance` and records a `face.attendance.log` audit entry.

Raw live scan photos are not uploaded to Odoo. Employee avatars stay in Odoo; encrypted templates are held in Odoo and a verified index is cached on the scanner phone.

## Odoo Setup

The Odoo addon is standalone and can be installed in any Odoo database with `hr` and `hr_attendance` available.

### 1. Install Addon

Copy `face_attendance/` into one of the target Odoo server's `addons_path` folders, or add this repository path to `addons_path`.

Example:

```ini
addons_path = /opt/odoo/odoo/addons,/opt/odoo/custom-addons
```

Restart Odoo, update the Apps list, and install **Face Attendance**.

CLI install:

```bash
./odoo-bin -c /path/to/odoo.conf -d TARGET_DATABASE -i face_attendance --stop-after-init
```

CLI upgrade:

```bash
./odoo-bin -c /path/to/odoo.conf -d TARGET_DATABASE -u face_attendance --stop-after-init
```

### 2. Assign Access

Assign HR/admin users to the relevant HR and Face Attendance groups:

- `Officer: Manage all employees`
- `Officer: Manage attendances`
- `Officer: Manage all attendances`
- `Face Attendance User`
- `Face Attendance Manager`

### 3. Configure Face Attendance

Open **Face Attendance > Configuration** and create or edit the active configuration.

Recommended starting values:

- Confidence threshold: `0.70`
- Liveness required: enabled
- Anti-spoofing required: enabled
- Active: enabled

These settings are stored in Odoo. Face recognition itself runs on the scanner phone.

### 4. Create Scanner Device

In **Face Attendance > Devices**:

1. Create a device.
2. Set device type to **Shared Scanner**.
3. Set a clear device UID, for example `shared-scanner-01`.
4. Save.
5. Copy the visible scanner setup code.
6. Enter that setup code in the Flutter scanner app.

The setup code becomes the scanner token stored on the phone.

### 5. Configure Template Worker and Backfill

Install the required packages into the same Python virtual environment that runs Odoo:

```bash
/path/to/odoo-venv/bin/pip install cryptography mediapipe numpy onnxruntime opencv-python-headless Pillow
```

Copy the bundled model once to the Odoo server, for example:

```bash
install -m 0644 face_attend_app/assets/models/w600k_r50.onnx /opt/odoo/models/w600k_r50.onnx
```

Set these server-side values outside source control:

- `FACE_ATTENDANCE_TEMPLATE_KEY`: a valid Fernet key used to encrypt templates at rest.
- `FACE_ATTENDANCE_ARCFACE_MODEL`: `/opt/odoo/models/w600k_r50.onnx`

The Odoo cron uses the bundled `w600k_r50.onnx` model and the same five-point ArcFace alignment as the phone. It processes only HR avatars and stores encrypted 512-float templates; it never receives live scanner photos.

Open **Face Attendance > Configuration** and select **Queue Template Backfill**. The one-minute cron processes up to 50 queued avatars per run. Use the visible pending/ready/failed counts to monitor the first backfill and **Retry Failed Templates** after correcting invalid HR avatars. New and changed avatars queue automatically.

### 6. Add Employees

For each employee:

1. Upload a real employee avatar with one clear face.
2. Save the employee.
3. Open the **Face Attendance** tab.
4. Confirm `Face Registered` is checked, or click **Prepare Avatar For Scanner**.

New or updated avatars become available to scanner phones after the template worker marks their central template ready. A new scanner waits for this central index rather than generating embeddings on the phone.

Avoid initials, placeholder images, group photos, side-face photos, blurry photos, or heavily cropped faces.

## Flutter Scanner Setup

```bash
cd face_attend_app
flutter pub get
flutter run
```

The scanner app is configured once with:

- Odoo URL
- Odoo database
- Scanner setup code

Employees do not log in to the scanner app. Employees do not manually register their faces in the app.

The scanner phone must be able to reach the Odoo server over the local network or internet. Use the machine/server IP address, not `localhost`, when configuring Odoo URL on a physical phone.

## Implemented Odoo API

- `POST /face_attendance/scanner/setup`
- `GET /face_attendance/scanner/index/manifest`
- `GET /face_attendance/scanner/index/chunk`
- `GET /face_attendance/status`
- `POST /face_attendance/punch`
- `POST /face_attendance/login` legacy employee-device endpoint
- `POST /face_attendance/enroll` disabled legacy endpoint
- `GET /face_attendance/template` disabled legacy endpoint

The active shared-scanner flow uses setup, scanner index, status, and punch.

## Deployment Requirements

Server side:

- Odoo with `hr` and `hr_attendance`
- `face_attendance` addon installed
- Network access from scanner phones to Odoo
- Odoo Python dependencies for ArcFace and a configured Fernet key

Phone side:

- Android phone with ARM64 support
- Good front camera
- Enough memory to run the bundled ArcFace ONNX model
- Flutter scanner APK installed

Odoo generates avatar embeddings centrally for enterprise scanner provisioning, while live scans stay on the phone.

## CI/CD

GitHub Actions verifies every push and pull request with Flutter analysis, tests, and a debug APK build. Pushing a `v*` tag additionally builds a signed release APK and distributes it through Firebase App Distribution.

Configure these GitHub environment secrets on `production` before creating a release tag: `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`, `ANDROID_STORE_PASSWORD`, `FIREBASE_APP_ID`, `FIREBASE_SERVICE_ACCOUNT`, and `FIREBASE_TESTER_GROUP`. The app's release keystore and all secrets stay out of this repository.

## Validation

Flutter:

```bash
cd face_attend_app
flutter analyze
flutter test
```

Manual checks:

- Configure scanner with Odoo URL, database, and scanner setup code.
- Sync employees from Odoo.
- Scan an indexed employee and confirm the correct employee is matched.
- Scan an unknown person and confirm attendance is rejected.
- Show two people and confirm the app asks for one person at a time.
- Check **Face Attendance > Logs** and **Attendances** in Odoo.

## Notes

The current recognition baseline is on-device ArcFace `w600k_r50.onnx` with InsightFace-compatible alignment. Keep scanner recognition changes isolated and test on real phones before changing thresholds or alignment logic.
