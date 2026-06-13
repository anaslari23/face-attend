# FaceAttend Scanner App

Flutter shared-scanner app for FaceAttend.

The phone is the ML engine. It syncs employee avatars from Odoo, creates local ArcFace embeddings, scans one face at a time, matches locally, and sends the attendance result to Odoo.

No FastAPI middleware is required.

## Run

```bash
flutter pub get
flutter run
```

## Configure

Enter:

- Odoo URL
- Odoo database
- scanner setup code generated in Odoo

Use the Odoo server IP or domain from the phone. Do not use `localhost` unless Odoo is running on the phone itself.

## Validate

```bash
flutter analyze
flutter test
```
