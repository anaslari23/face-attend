import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class DatabaseHelper {
  DatabaseHelper._privateConstructor();
  static final DatabaseHelper instance = DatabaseHelper._privateConstructor();

  static const String _dbName = 'face_attend.db';
  static const int _dbVersion = 1;

  Database? _db;

  Future<Database> get database async {
    if (_db != null && _db!.isOpen) return _db!;
    _db = await _initDatabase();
    return _db!;
  }

  Future<Database> _initDatabase() async {
    // If desktop (macOS/Windows/Linux) in debug or CLI mode, initialize sqflite ffi if needed
    if (!kIsWeb &&
        (Platform.isMacOS || Platform.isLinux || Platform.isWindows)) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final documentsDir = await getApplicationDocumentsDirectory();
    final path = p.join(documentsDir.path, _dbName);

    debugPrint('Initializing SQLite database at: $path');

    return await openDatabase(path, version: _dbVersion, onCreate: _onCreate);
  }

  Future<void> _onCreate(Database db, int version) async {
    debugPrint('Creating SQLite database tables for FaceAttend...');

    // 1. Punch Logs Table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS punch_logs (
        id TEXT PRIMARY KEY,
        timestamp TEXT NOT NULL,
        employee_name TEXT NOT NULL,
        is_synced INTEGER NOT NULL DEFAULT 0,
        sync_error TEXT,
        payload_json TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');

    // 2. Face Embeddings Table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS face_embeddings (
        employee_id INTEGER PRIMARY KEY,
        employee_name TEXT NOT NULL,
        department TEXT,
        avatar_write_date TEXT NOT NULL,
        primary_embedding_json TEXT NOT NULL,
        adaptive_embeddings_json TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    // 3. App Sessions Table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS app_sessions (
        key TEXT PRIMARY KEY,
        base_url TEXT NOT NULL,
        db TEXT NOT NULL,
        token TEXT NOT NULL,
        device_id TEXT NOT NULL,
        device_name TEXT NOT NULL,
        generated_device_id TEXT,
        updated_at TEXT NOT NULL
      )
    ''');

    // 4. App Settings Table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS app_settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
  }

  // ===========================================================================
  // PUNCH LOG OPERATIONS
  // ===========================================================================

  Future<void> insertPunchLog({
    required String id,
    required DateTime timestamp,
    required String employeeName,
    required bool isSynced,
    String? syncError,
    required Map<String, dynamic> payload,
  }) async {
    final db = await database;
    final row = {
      'id': id,
      'timestamp': timestamp.toIso8601String(),
      'employee_name': employeeName,
      'is_synced': isSynced ? 1 : 0,
      'sync_error': syncError,
      'payload_json': jsonEncode(payload),
      'created_at': DateTime.now().toIso8601String(),
    };

    await db.insert(
      'punch_logs',
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    debugPrint('SQLite: Saved punch log $id (synced: $isSynced)');
  }

  Future<List<Map<String, dynamic>>> getAllPunchLogs() async {
    final db = await database;
    final maps = await db.query('punch_logs', orderBy: 'timestamp DESC');
    return maps.map((row) {
      return {
        'id': row['id'] as String,
        'timestamp': row['timestamp'] as String,
        'employeeName': row['employee_name'] as String,
        'isSynced': (row['is_synced'] as int) == 1,
        'syncError': row['sync_error'] as String?,
        'payload': jsonDecode(row['payload_json'] as String),
      };
    }).toList();
  }

  Future<void> updatePunchLogSyncStatus(
    String id, {
    required bool isSynced,
    String? syncError,
  }) async {
    final db = await database;
    await db.update(
      'punch_logs',
      {'is_synced': isSynced ? 1 : 0, 'sync_error': syncError},
      where: 'id = ?',
      whereArgs: [id],
    );
    debugPrint('SQLite: Updated log $id sync status -> $isSynced');
  }

  Future<void> pruneOldLogs(DateTime cutoff) async {
    final db = await database;
    final cutoffIso = cutoff.toIso8601String();
    final count = await db.delete(
      'punch_logs',
      where: 'timestamp < ?',
      whereArgs: [cutoffIso],
    );
    if (count > 0) {
      debugPrint('SQLite: Pruned $count old punch logs prior to $cutoffIso');
    }
  }

  Future<void> clearAllPunchLogs() async {
    final db = await database;
    await db.delete('punch_logs');
    debugPrint('SQLite: Cleared all punch logs');
  }

  // ===========================================================================
  // FACE EMBEDDING OPERATIONS
  // ===========================================================================

  Future<void> saveFaceRecord({
    required int employeeId,
    required String employeeName,
    String? department,
    required String avatarWriteDate,
    required List<double> primaryEmbedding,
    required List<List<double>> adaptiveEmbeddings,
  }) async {
    final db = await database;
    await db.insert('face_embeddings', {
      'employee_id': employeeId,
      'employee_name': employeeName,
      'department': department,
      'avatar_write_date': avatarWriteDate,
      'primary_embedding_json': jsonEncode(primaryEmbedding),
      'adaptive_embeddings_json': jsonEncode(adaptiveEmbeddings),
      'updated_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> getFaceRecords() async {
    final db = await database;
    final rows = await db.query('face_embeddings');
    return rows.map((row) {
      return {
        'employee_id': row['employee_id'] as int,
        'employee_name': row['employee_name'] as String,
        'department': row['department'] as String?,
        'avatar_write_date': row['avatar_write_date'] as String,
        'primary_embedding':
            (jsonDecode(row['primary_embedding_json'] as String)
                    as List<dynamic>)
                .map((v) => (v as num).toDouble())
                .toList(),
        'adaptive_embeddings':
            (jsonDecode(row['adaptive_embeddings_json'] as String)
                    as List<dynamic>)
                .map(
                  (list) => (list as List<dynamic>)
                      .map((v) => (v as num).toDouble())
                      .toList(),
                )
                .toList(),
      };
    }).toList();
  }

  Future<void> clearFaceRecords() async {
    final db = await database;
    await db.delete('face_embeddings');
  }

  // ===========================================================================
  // APP SESSION OPERATIONS
  // ===========================================================================

  Future<void> saveSession(Map<String, dynamic> sessionMap) async {
    final db = await database;
    await db.insert('app_sessions', {
      'key': 'active_session',
      'base_url': sessionMap['baseUrl'] ?? '',
      'db': sessionMap['db'] ?? '',
      'token': sessionMap['token'] ?? '',
      'device_id': sessionMap['deviceId'] ?? '',
      'device_name': sessionMap['deviceName'] ?? '',
      'generated_device_id': sessionMap['generatedDeviceId'],
      'updated_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    debugPrint(
      'SQLite: Saved active session for device: ${sessionMap['deviceName']}',
    );
  }

  Future<Map<String, dynamic>?> getSession() async {
    final db = await database;
    final rows = await db.query(
      'app_sessions',
      where: 'key = ?',
      whereArgs: ['active_session'],
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    return {
      'baseUrl': row['base_url'],
      'db': row['db'],
      'token': row['token'],
      'deviceId': row['device_id'],
      'deviceName': row['device_name'],
      'generatedDeviceId': row['generated_device_id'],
    };
  }

  Future<void> clearSession() async {
    final db = await database;
    await db.delete(
      'app_sessions',
      where: 'key = ?',
      whereArgs: ['active_session'],
    );
  }

  // ===========================================================================
  // SETTINGS & SECRET TOKEN
  // ===========================================================================

  Future<String> getSecretToken() async {
    final db = await database;
    final rows = await db.query(
      'app_settings',
      where: 'key = ?',
      whereArgs: ['secret_admin_token'],
    );
    if (rows.isNotEmpty) {
      return rows.first['value'] as String;
    }
    return '';
  }

  Future<void> setSecretToken(String token) async {
    final db = await database;
    await db.insert('app_settings', {
      'key': 'secret_admin_token',
      'value': token,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ===========================================================================
  // DATABASE DUMP / EXPORT
  // ===========================================================================

  Future<Map<String, dynamic>> exportFullDatabaseToJson() async {
    final logs = await getAllPunchLogs();
    final faces = await getFaceRecords();
    final session = await getSession();
    final secretToken = await getSecretToken();

    return {
      'export_timestamp': DateTime.now().toIso8601String(),
      'database_name': _dbName,
      'tables': {
        'punch_logs': logs,
        'face_embeddings': faces,
        'app_sessions': session,
        'secret_token': secretToken,
      },
      'stats': {
        'total_logs': logs.length,
        'synced_logs': logs.where((l) => l['isSynced'] == true).length,
        'pending_logs': logs.where((l) => l['isSynced'] == false).length,
        'total_indexed_employees': faces.length,
      },
    };
  }

  // ===========================================================================
  // MIGRATION FROM LEGACY JSON FILES
  // ===========================================================================

  Future<void> migrateLegacyFilesIfNeeded() async {
    try {
      final db = await database;

      // 1. Check if punch_logs is empty, and migrate face_attend_punch_logs.json if present
      final countResult = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM punch_logs'),
      );
      if (countResult == 0) {
        final docsDir = await getApplicationDocumentsDirectory();
        final jsonFile = File('${docsDir.path}/face_attend_punch_logs.json');
        if (await jsonFile.exists()) {
          final content = await jsonFile.readAsString();
          final decoded = jsonDecode(content) as List<dynamic>;
          debugPrint(
            'SQLite Migration: Migrating ${decoded.length} legacy JSON logs to SQLite...',
          );
          for (final item in decoded) {
            final m = item as Map<String, dynamic>;
            final id =
                m['id'] as String? ??
                'log_${DateTime.now().millisecondsSinceEpoch}';
            final ts =
                DateTime.tryParse(m['timestamp'] as String? ?? '') ??
                DateTime.now();
            final empName = m['employeeName'] as String? ?? 'Unknown';
            final isSynced = m['isSynced'] as bool? ?? false;
            final syncError = m['syncError'] as String?;
            final payload = Map<String, dynamic>.from(
              m['payload'] as Map? ?? {},
            );

            await insertPunchLog(
              id: id,
              timestamp: ts,
              employeeName: empName,
              isSynced: isSynced,
              syncError: syncError,
              payload: payload,
            );
          }
          debugPrint('SQLite Migration: Punch log migration complete.');
        }
      }

      // 2. Migrate cached face embeddings if present in JSON file
      final faceCount = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM face_embeddings'),
      );
      if (faceCount == 0) {
        final supportDir = await getApplicationSupportDirectory();
        final embeddingFile = File(
          '${supportDir.path}/face_attend_local_embeddings.json',
        );
        if (await embeddingFile.exists()) {
          final content = await embeddingFile.readAsString();
          final payload = jsonDecode(content) as Map<String, dynamic>;
          final records = payload['records'] as List<dynamic>? ?? [];
          debugPrint(
            'SQLite Migration: Migrating ${records.length} legacy face embedding records to SQLite...',
          );
          for (final rec in records) {
            final r = rec as Map<String, dynamic>;
            final empId = r['employee_id'] as int;
            final empName = r['employee_name'] as String;
            final dept = r['department'] as String?;
            final writeDate = r['avatar_write_date'] as String? ?? '';
            final primary = (r['primary_embedding'] as List<dynamic>? ?? [])
                .map((v) => (v as num).toDouble())
                .toList();
            final adaptive = (r['adaptive_embeddings'] as List<dynamic>? ?? [])
                .map(
                  (list) => (list as List<dynamic>)
                      .map((v) => (v as num).toDouble())
                      .toList(),
                )
                .toList();

            await saveFaceRecord(
              employeeId: empId,
              employeeName: empName,
              department: dept,
              avatarWriteDate: writeDate,
              primaryEmbedding: primary,
              adaptiveEmbeddings: adaptive,
            );
          }
          debugPrint('SQLite Migration: Face embedding migration complete.');
        }
      }
    } catch (e) {
      debugPrint('SQLite Migration Exception: $e');
    }
  }
}
