import 'dart:convert';
import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main(List<String> args) async {
  final home = Platform.environment['HOME'];
  if (home == null) {
    print('Error: Could not find HOME environment variable.');
    exit(1);
  }

  // Initialize SQLite FFI for Dart CLI
  sqfliteFfiInit();
  final databaseFactory = databaseFactoryFfi;

  // Potential search paths for face_attend.db on macOS/Linux/iOS simulator
  final searchPaths = [
    'face_attend.db',
    '.face_attend_pulled.db',
    '$home/Documents/face_attend.db',
    '$home/Library/Containers/com.example.faceAttendApp/Data/Documents/face_attend.db',
    '$home/Library/Application Support/com.example.faceAttendApp/face_attend.db',
    '$home/.local/share/com.example.face_attend_app/face_attend.db',
  ];

  File? dbFile;
  for (final path in searchPaths) {
    final file = File(path);
    if (await file.exists()) {
      dbFile = file;
      break;
    }
  }

  // If not found in local paths, try to pull it from a connected Android device/emulator
  if (dbFile == null) {
    try {
      final devicesResult = await Process.run('adb', ['devices']);
      if (devicesResult.exitCode == 0) {
        final devicesOutput = devicesResult.stdout.toString();
        // Check if there are any active devices listed (excluding the header line "List of devices attached")
        final hasDevice = devicesOutput.split('\n')
            .any((line) => line.trim().isNotEmpty && !line.startsWith('List of devices') && line.contains('device'));
        
        if (hasDevice) {
          print('No local database file found. Android device/emulator detected via ADB.');
          print('Attempting to pull database from device...');
          
          final pullResult = await Process.run(
            'adb',
            [
              'exec-out',
              'run-as',
              'com.example.face_attend_app',
              'cat',
              'app_flutter/face_attend.db'
            ],
            stdoutEncoding: null,
          );
          
          if (pullResult.exitCode == 0 && pullResult.stdout is List<int>) {
            final bytes = pullResult.stdout as List<int>;
            if (bytes.isNotEmpty) {
              final header = String.fromCharCodes(bytes.take(15));
              if (header.startsWith('SQLite format 3')) {
                final file = File('.face_attend_pulled.db');
                await file.writeAsBytes(bytes);
                dbFile = file;
                print('Successfully pulled database from Android device to local: ${file.path}\n');
              } else {
                print('ADB: Connection succeeded but did not return a valid SQLite file (possibly empty or no permission).\n');
              }
            }
          } else {
            print('ADB: Failed to pull database file from device (run-as command failed or app not debuggable).\n');
          }
        }
      }
    } catch (_) {
      // adb command probably not installed/available or failed, ignore and continue
    }
  }

  // Recursive search if not found in standard paths
  if (dbFile == null) {
    final dirsToSearch = [
      Directory('$home/Documents'),
      Directory('$home/Library/Containers'),
      Directory('$home/.local/share'),
    ];

    for (final dir in dirsToSearch) {
      if (await dir.exists()) {
        try {
          await for (final entity in dir.list(recursive: true, followLinks: false)) {
            if (entity is File && entity.path.endsWith('face_attend.db')) {
              dbFile = entity;
              break;
            }
          }
        } catch (_) {}
      }
      if (dbFile != null) break;
    }
  }

  // Fallback check for legacy JSON if DB file isn't created yet
  if (dbFile == null) {
    print('Warning: SQLite database face_attend.db not found yet.');
    print('Checking legacy JSON logs fallback...\n');
    _printLegacyJsonLogs(home);
    return;
  }

  print('================================================================');
  print('          FLUTTER SQFLITE DATABASE INSPECTOR & EXPORTER        ');
  print('================================================================');
  print('Database Path : ${dbFile.absolute.path}');
  print('File Size     : ${await dbFile.length()} bytes\n');

  Database? db;
  try {
    db = await databaseFactory.openDatabase(
      dbFile.absolute.path,
      options: OpenDatabaseOptions(readOnly: true),
    );

    // 1. Fetch Punch Logs
    List<Map<String, dynamic>> punchLogs = [];
    try {
      punchLogs = await db.query('punch_logs', orderBy: 'timestamp DESC');
    } catch (e) {
      print('Note: punch_logs table query error: $e');
    }

    // 2. Fetch Face Embeddings
    List<Map<String, dynamic>> faceEmbeddings = [];
    try {
      faceEmbeddings = await db.query('face_embeddings');
    } catch (e) {
      print('Note: face_embeddings table query error: $e');
    }

    // 3. Fetch App Session
    List<Map<String, dynamic>> appSessions = [];
    try {
      appSessions = await db.query('app_sessions');
    } catch (e) {
      print('Note: app_sessions table query error: $e');
    }

    // 4. Fetch App Settings
    List<Map<String, dynamic>> appSettings = [];
    try {
      appSettings = await db.query('app_settings');
    } catch (e) {
      print('Note: app_settings table query error: $e');
    }

    final syncedCount = punchLogs.where((l) => (l['is_synced'] as int? ?? 0) == 1).length;
    final unsyncedCount = punchLogs.length - syncedCount;

    print('====================== DATABASE SUMMARY ======================');
    print('Total Punch Logs     : ${punchLogs.length}');
    print('  - Synced Logs      : $syncedCount');
    print('  - Pending Offline  : $unsyncedCount');
    print('Indexed Face Records : ${faceEmbeddings.length}');
    print('Active Sessions      : ${appSessions.length}');
    print('==============================================================\n');

    print('=================== 1. PUNCH & ATTENDANCE LOGS ===================');
    if (punchLogs.isEmpty) {
      print('No punch logs found in database.');
    } else {
      for (int i = 0; i < punchLogs.length; i++) {
        final row = punchLogs[i];
        final id = row['id'] ?? 'N/A';
        final timestamp = row['timestamp'] ?? 'N/A';
        final empName = row['employee_name'] ?? 'Unknown';
        final isSynced = (row['is_synced'] as int? ?? 0) == 1;
        final syncError = row['sync_error'] as String?;
        Map<String, dynamic> payload = {};
        try {
          payload = jsonDecode(row['payload_json'] as String? ?? '{}') as Map<String, dynamic>;
        } catch (_) {}

        print('[$i] Log ID : $id');
        print('    Time   : $timestamp');
        print('    Emp    : $empName');
        print('    Synced : ${isSynced ? "YES" : "NO (PENDING OFFLINE)"}');
        if (syncError != null && syncError.isNotEmpty) {
          print('    Error  : $syncError');
        }
        print('    Payload Details:');
        payload.forEach((key, val) {
          print('      $key: $val');
        });
        print('----------------------------------------------------');
      }
    }

    print('\n=================== 2. CACHED FACE EMBEDDINGS ===================');
    if (faceEmbeddings.isEmpty) {
      print('No face embeddings found in database.');
    } else {
      for (int i = 0; i < faceEmbeddings.length; i++) {
        final r = faceEmbeddings[i];
        final empId = r['employee_id'];
        final empName = r['employee_name'];
        final dept = r['department'] ?? 'N/A';
        final writeDate = r['avatar_write_date'];
        List<dynamic> primary = [];
        try {
          primary = jsonDecode(r['primary_embedding_json'] as String? ?? '[]');
        } catch (_) {}

        print('[$i] Employee ID : $empId | Name: $empName | Dept: $dept');
        print('    Avatar Write Date: $writeDate');
        print('    Primary Vector Dim: ${primary.length} dimensions');
        print('----------------------------------------------------');
      }
    }

    print('\n=================== 3. APP SESSION & CONFIG ===================');
    if (appSessions.isEmpty) {
      print('No active session saved.');
    } else {
      final s = appSessions.first;
      print('Base URL      : ${s['base_url']}');
      print('Database      : ${s['db']}');
      print('Device ID     : ${s['device_id']}');
      print('Device Name   : ${s['device_name']}');
      print('Token         : ${s['token']}');
    }
    for (final setting in appSettings) {
      print('Setting [${setting['key']}] : ${setting['value']}');
    }

    print('\n================================================================');
    print('            FULL JSON DATABASE DUMP FOR TERMINAL COPY           ');
    print('================================================================');

    final fullDump = {
      'db_file_path': dbFile.path,
      'exported_at': DateTime.now().toIso8601String(),
      'tables': {
        'punch_logs': punchLogs.map((row) {
          final copy = Map<String, dynamic>.from(row);
          try {
            copy['payload'] = jsonDecode(row['payload_json'] as String? ?? '{}');
          } catch (_) {}
          return copy;
        }).toList(),
        'face_embeddings': faceEmbeddings,
        'app_sessions': appSessions,
        'app_settings': appSettings,
      }
    };

    print(const JsonEncoder.withIndent('  ').convert(fullDump));
    print('================================================================\n');

  } catch (e) {
    print('Error opening or reading SQLite database: $e');
  } finally {
    await db?.close();
  }
}

void _printLegacyJsonLogs(String home) async {
  final searchPaths = [
    '$home/Documents/face_attend_punch_logs.json',
    '$home/.local/share/com.example.face_attend_app/face_attend_punch_logs.json',
  ];
  for (final path in searchPaths) {
    final file = File(path);
    if (await file.exists()) {
      print('Found legacy JSON logs at: ${file.path}');
      print(await file.readAsString());
      return;
    }
  }
  print('No local logs found.');
}
