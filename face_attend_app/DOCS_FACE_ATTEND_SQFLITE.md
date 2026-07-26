# 📘 FaceAttend: Complete App Architecture, SQLite Storage & Offline Workflow Guide

Welcome to the comprehensive guide for **FaceAttend**! This document explains how the entire application operates under the hood, how SQLite (`sqflite`) manages your data, how offline attendance scanning works, and how you can inspect, dump, and debug the database using both terminal commands and secret in-app views.

---

## 🌟 1. Overview & Core Philosophy

**FaceAttend** is a high-performance, offline-first biometric phone attendance app designed to connect with Odoo backends. 

### Core Guarantee:
> **No Punch Is Ever Lost!**
> Whether a face scan succeeds, fails, loses network connection, encounters a server error, or triggers a cooldown, the app **instantly writes the punch record into local SQLite storage** (`face_attend.db`). When internet access returns, background auto-sync pushes all pending logs to Odoo.

---

## 🔄 2. Complete Step-by-Step App Process

Here is the exact journey of a punch scan from start to finish:

```
[ Camera Scan ] ➡️ [ On-Device Biometric Match ] ➡️ [ Instant SQLite Log ] ➡️ [ Odoo Backend Sync ]
       │                         │                          │                      │
(Detects face &            (Matches 512-d ArcFace    (Saves to SQLite table    (Pushes log if online;
liveness score)             vector offline)           `punch_logs` immediately)   retries if offline)
```

1. **App Launch & Migration**:
   - On startup, `main()` initializes `DatabaseHelper` and automatically migrates any old JSON log files (`face_attend_punch_logs.json`) or legacy secure session files into the SQLite database (`face_attend.db`).
2. **Session Setup & Employee Face Sync**:
   - The admin logs into Odoo. The app fetches employee profiles and their avatar images.
   - The app runs high-speed local embedding extraction (ArcFace model) to convert faces into 512-dimensional numerical vectors.
   - These vectors are stored in SQLite (`face_embeddings` table) for offline use.
3. **Offline Face Scanning & Match**:
   - The camera analyzes live video frames for faces and verifies liveness.
   - When a clear frame is captured, `OnDeviceFaceMatcher` calculates the cosine similarity score against all employee vectors stored in SQLite.
4. **Guaranteed Local Logging**:
   - Before attempting any network call, `LocalLogService.instance.addLog()` writes the full punch payload (timestamp, confidence score, liveness score, employee name, device ID) to the `punch_logs` SQLite table with `is_synced = 0`.
5. **Backend Punch & Auto-Sync**:
   - If connected, the app immediately sends the punch to Odoo and updates `is_synced = 1`.
   - If offline or if Odoo is unreachable, the punch stays safely marked as `is_synced = 0` (Pending Offline). The `startAutoSync` background service periodically retries pushing unsynced logs whenever connectivity returns.

---

## 🗄️ 3. How SQLite Storage Works (`DatabaseHelper`)

All application state is stored locally inside the SQLite database file **`face_attend.db`**.

### Database Schema Tables:

1. **`punch_logs`** (Attendance & Scans):
   - `id`: Unique string identifier (e.g. `log_1721980000_12`)
   - `timestamp`: ISO8601 local timestamp
   - `employee_name`: Employee name or failure label
   - `is_synced`: `1` (Synced to Odoo) or `0` (Pending offline)
   - `sync_error`: Detailed error message if server call failed
   - `payload_json`: Complete raw JSON payload of the scan
   - `created_at`: Creation timestamp

2. **`face_embeddings`** (Offline Face Recognition):
   - `employee_id`: Odoo employee ID (Primary Key)
   - `employee_name`: Employee full name
   - `department`: Employee department
   - `avatar_write_date`: Odoo avatar update timestamp
   - `primary_embedding_json`: 512-dimensional vector list
   - `adaptive_embeddings_json`: Up to 5 learned facial variation vectors
   - `updated_at`: Last sync date

3. **`app_sessions`** (Authentication Credentials):
   - `key`: `'active_session'`
   - `base_url`, `db`, `token`, `device_id`, `device_name`, `generated_device_id`

4. **`app_settings`** (Configuration):
   - `secret_admin_token`: Default is set to **`ADMIN123`**

---

## 💻 4. Running the App on Target Platforms

Use these terminal commands from the project directory (`face_attend_app`):

### 🍏 Run on macOS Desktop:
```bash
flutter run -d macos
```

### 📱 Run on Android (Physical Device or Emulator):
```bash
flutter run
```
*(If multiple devices are connected, select your Android device from the list or run `flutter run -d <device_id>`)*

### 🌐 Run on Chrome / Web:
```bash
flutter run -d chrome
```

---

## 🛠️ 5. Inspecting & Dumping Database via Terminal

You can inspect the entire SQLite database directly in your terminal at any time with a single command!

### Terminal Database Inspection Command:
```bash
dart print_logs.dart
```
*(Alternative alias: `dart run print_db.dart`)*

### What the Terminal Command Does:
1. Locates `face_attend.db` on your computer.
2. Displays a formatted **Database Summary**: Total logs count, synced count, pending offline count, and cached face records count.
3. Prints every **Punch & Attendance Log** with date, employee name, sync status, error reason, and full payload details.
4. Prints **Cached Face Record Summaries** (Employee names and 512-d vector status).
5. Prints active **Session & Device Configuration**.
6. Generates a **Full Formatted JSON Database Dump** at the end so you can easily copy, paste, or send your entire database content to anyone.

---

## 🔐 6. Secret Token Database Inspector (In-App UI)

We built a hidden, state-of-the-art **Database & Offline Inspector** view directly inside the Flutter app interface!

### How to Unlock the Secret View:
1. Open the app on your phone, macOS desktop, or emulator.
2. **Method A**: Tap the **gold shield icon** (`admin_panel_settings`) in the top app bar.
3. **Method B**: **Long-press** the **"PISmartPunch"** app title in the top bar.
4. Enter the Secret Admin Token: **`ADMIN123`**
5. Tap **Unlock View**.

### Features Inside the Database Inspector Dashboard:
- 📋 **Punch Logs Tab**: Search and filter logs in real time by employee name, ID, or error status. Tap any log card to expand and view its full raw JSON payload.
- 👤 **Face Index Tab**: View all cached employees, their primary 512-d ArcFace vector status, and adaptive variants stored in SQLite.
- 🔑 **Session & Security Tab**: View active Odoo URL, database name, token, and change/update your secret admin token.
- 📄 **JSON Dump Tab**: View the complete SQLite database output in a raw code format with a single-tap **"Copy JSON"** or **"Share"** button!

---

## 💡 Quick Reference Summary

| Task | Command / Gesture |
| :--- | :--- |
| **Run on macOS** | `flutter run -d macos` |
| **Run on Android** | `flutter run` |
| **Terminal DB Inspector** | `dart print_logs.dart` |
| **Default Secret Token** | `ADMIN123` |
| **Unlock Secret View** | Long-press app header or tap shield icon |
| **Database File Name** | `face_attend.db` |

Now you have full control over your offline attendance logs, SQLite database, terminal tools, and secret inspection features! 🚀
