import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../api/odoo_face_attendance_client.dart';
import 'database_helper.dart';

class LocalPunchLog {
  LocalPunchLog({
    required this.id,
    required this.timestamp,
    required this.payload,
    required this.employeeName,
    required this.isSynced,
    this.syncError,
  });

  final String id;
  final DateTime timestamp;
  final Map<String, dynamic> payload;
  final String employeeName;
  bool isSynced;
  String? syncError;

  factory LocalPunchLog.fromJson(Map<String, dynamic> json) {
    return LocalPunchLog(
      id: json['id'] as String? ?? '',
      timestamp:
          DateTime.tryParse(json['timestamp'] as String? ?? '') ??
          DateTime.now(),
      payload: Map<String, dynamic>.from(json['payload'] as Map? ?? {}),
      employeeName: json['employeeName'] as String? ?? 'Unknown Employee',
      isSynced: json['isSynced'] as bool? ?? false,
      syncError: json['syncError'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'timestamp': timestamp.toIso8601String(),
    'payload': payload,
    'employeeName': employeeName,
    'isSynced': isSynced,
    'syncError': syncError,
  };
}

class LocalLogService {
  LocalLogService._privateConstructor();
  static final LocalLogService instance = LocalLogService._privateConstructor();

  static const _fileName = 'face_attend_punch_logs.json';
  static const _maxLogCount = 1000;

  List<LocalPunchLog>? _cache;

  // ---- Auto-sync state ----
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  Timer? _syncTimer;
  OdooFaceAttendanceClient? _syncClient;
  bool _isSyncing = false;

  Future<File> _getLogFile() async {
    final directory = await getApplicationDocumentsDirectory();

    debugPrint("========================================");
    debugPrint("Documents Directory: ${directory.path}");

    final file = File('${directory.path}/$_fileName');

    debugPrint("Log File Path: ${file.path}");

    final exists = await file.exists();
    debugPrint("File Exists: $exists");

    if (exists) {
      final content = await file.readAsString();
      debugPrint("========== LOCAL LOG FILE CONTENT ==========");
      debugPrint(content);
      debugPrint("===========================================");
    } else {
      debugPrint("Local log file does not exist yet.");
    }

    return file;
  }

  DateTime _getCutoffDate(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final deleteTime = DateTime(now.year, now.month, now.day, 23, 50);
    if (now.isBefore(deleteTime)) {
      // Before 11:50 PM, we keep data from 6 days ago (e.g. June 24th if today is June 30th)
      return today.subtract(const Duration(days: 6));
    } else {
      // At or after 11:50 PM, the 6-days-ago data is deleted, so the cutoff is June 25th (5 days ago)
      return today.subtract(const Duration(days: 5));
    }
  }

  @visibleForTesting
  DateTime getCutoffDateForTesting(DateTime now) => _getCutoffDate(now);

  @visibleForTesting
  void setCacheForTesting(List<LocalPunchLog>? mockCache) {
    _cache = mockCache;
  }

  Future<void> pruneOldLogs() async {
    final cutoff = _getCutoffDate(DateTime.now());
    await DatabaseHelper.instance.pruneOldLogs(cutoff);
    final logs = await getLogs();
    final pruned = logs
        .where(
          (log) =>
              log.timestamp.isAfter(cutoff) ||
              log.timestamp.isAtSameMomentAs(cutoff),
        )
        .toList();
    await saveLogs(pruned);
  }

  Future<List<LocalPunchLog>> getLogs() async {
    if (_cache != null) {
      return _cache!;
    }
    try {
      await DatabaseHelper.instance.migrateLegacyFilesIfNeeded();
      final dbLogs = await DatabaseHelper.instance.getAllPunchLogs();
      _cache = dbLogs.map((item) => LocalPunchLog.fromJson(item)).toList();
      _cache!.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      // Prune logs older than our cutoff
      final cutoff = _getCutoffDate(DateTime.now());
      final originalLength = _cache!.length;
      _cache = _cache!
          .where(
            (log) =>
                log.timestamp.isAfter(cutoff) ||
                log.timestamp.isAtSameMomentAs(cutoff),
          )
          .toList();

      if (_cache!.length < originalLength) {
        saveLogs(_cache!);
      }

      return _cache!;
    } catch (e) {
      debugPrint('Error reading SQLite logs: $e');
      _cache = [];
      return _cache!;
    }
  }

  Future<void> saveLogs(List<LocalPunchLog> logs) async {
    try {
      _cache = List.from(logs);
      _cache!.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      final cutoff = _getCutoffDate(DateTime.now());
      _cache = _cache!
          .where(
            (log) =>
                log.timestamp.isAfter(cutoff) ||
                log.timestamp.isAtSameMomentAs(cutoff),
          )
          .toList();

      if (_cache!.length > _maxLogCount) {
        _cache = _cache!.sublist(0, _maxLogCount);
      }

      // Save to SQLite for each log
      for (final log in _cache!) {
        await DatabaseHelper.instance.insertPunchLog(
          id: log.id,
          timestamp: log.timestamp,
          employeeName: log.employeeName,
          isSynced: log.isSynced,
          syncError: log.syncError,
          payload: log.payload,
        );
      }

      // Maintain legacy JSON file backup
      final file = await _getLogFile();
      final jsonList = _cache!.map((log) => log.toJson()).toList();
      await file.writeAsString(jsonEncode(jsonList));
    } catch (e) {
      debugPrint('Error saving local logs to SQLite/JSON: $e');
    }
  }

  Future<void> addLog({
    required String id,
    required DateTime timestamp,
    required Map<String, dynamic> payload,
    required String employeeName,
    required bool isSynced,
    String? syncError,
  }) async {
    // 1. Immediately insert into SQLite database
    await DatabaseHelper.instance.insertPunchLog(
      id: id,
      timestamp: timestamp,
      employeeName: employeeName,
      isSynced: isSynced,
      syncError: syncError,
      payload: payload,
    );

    // 2. Update memory cache and JSON fallback
    final logs = await getLogs();
    final newLog = LocalPunchLog(
      id: id,
      timestamp: timestamp,
      payload: payload,
      employeeName: employeeName,
      isSynced: isSynced,
      syncError: syncError,
    );
    logs.insert(0, newLog);
    await saveLogs(logs);
  }

  Future<void> updateLogSyncStatus(
    String id, {
    required bool isSynced,
    String? syncError,
  }) async {
    // 1. Update in SQLite
    await DatabaseHelper.instance.updatePunchLogSyncStatus(
      id,
      isSynced: isSynced,
      syncError: syncError,
    );

    // 2. Update in memory cache & JSON
    final logs = await getLogs();
    final index = logs.indexWhere((log) => log.id == id);
    if (index != -1) {
      logs[index].isSynced = isSynced;
      logs[index].syncError = syncError;
      await saveLogs(logs);
    }
  }


  String _backendTimestamp(DateTime timestamp) {
    return timestamp.toUtc().toIso8601String();
  }

  Map<String, dynamic> _fullLogData(
    LocalPunchLog log,
    String backendTimestamp,
  ) {
    return {
      'local_log_id': log.id,
      'local_timestamp': log.timestamp.toIso8601String(),
      'backend_timestamp': backendTimestamp,
      'employee_name': log.employeeName,
      'is_synced': log.isSynced,
      'sync_error': log.syncError,
      'payload': log.payload,
    };
  }

  @visibleForTesting
  String backendTimestampForTesting(DateTime timestamp) {
    return _backendTimestamp(timestamp);
  }

  Future<int> syncPendingLogs(OdooFaceAttendanceClient client) async {
    final logs = await getLogs();

    final pending = logs.where((log) => !log.isSynced).toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    // ============================================================
    // PRINT ALL PENDING (NOT SYNCED) LOGS
    // ============================================================
    debugPrint("");
    debugPrint("=======================================================");
    debugPrint("           PENDING (NOT SYNCED) LOGS");
    debugPrint("=======================================================");
    debugPrint("Total Pending Logs : ${pending.length}");

    if (pending.isEmpty) {
      debugPrint("No pending logs found.");
      debugPrint("=======================================================");
      return 0;
    }

    for (int i = 0; i < pending.length; i++) {
      final log = pending[i];

      debugPrint("");
      debugPrint(
        "--------------- Pending Log ${i + 1}/${pending.length} ---------------",
      );
      debugPrint("Local Log ID : ${log.id}");
      debugPrint("Employee     : ${log.employeeName}");
      debugPrint("Timestamp    : ${log.timestamp.toIso8601String()}");
      debugPrint("Is Synced    : ${log.isSynced}");
      debugPrint("Sync Error   : ${log.syncError ?? 'None'}");

      debugPrint("Payload:");
      debugPrint(const JsonEncoder.withIndent('  ').convert(log.payload));

      debugPrint("-------------------------------------------------------");
    }

    debugPrint("=======================================================");
    debugPrint("");

    // ============================================================
    // START SYNC
    // ============================================================

    int successCount = 0;
    bool needsSave = false;

    for (final log in pending) {
      try {
        final p = log.payload;

        // Send UTC so Odoo does not apply the device timezone offset twice.
        final originalTimestampStr = _backendTimestamp(log.timestamp);

        debugPrint("");
        debugPrint("SYNCING LOG : ${log.id}");
        debugPrint("Employee    : ${log.employeeName}");
        debugPrint("Timestamp   : $originalTimestampStr");

        final result = await client.punch(
          accepted: p['accepted'] as bool? ?? false,
          matchedEmployeeId: p['matched_employee_id'] as int?,
          matchScore: (p['match_score'] as num? ?? 0.0).toDouble(),
          threshold: (p['threshold'] as num? ?? 0.70).toDouble(),
          deviceId: p['device_id'] as String? ?? '',
          appVersion: p['app_version'] as String? ?? '1.0.0',
          failureReason: p['failure_reason'] as String?,
          secondBestConfidence: p['second_best_confidence'] != null
              ? (p['second_best_confidence'] as num).toDouble()
              : null,
          embeddingSource: p['embedding_source'] as String?,
          reviewEmbeddingId: p['review_embedding_id'] as int?,
          needsReview: p['needs_review'] as bool? ?? false,
          livenessPassed: p['liveness_passed'] as bool? ?? false,
          livenessScore: p['liveness_score'] != null
              ? (p['liveness_score'] as num).toDouble()
              : null,
          spoofScore: p['spoof_score'] != null
              ? (p['spoof_score'] as num).toDouble()
              : null,
          timestamp: originalTimestampStr,
          punchTime: originalTimestampStr,
          fullLogData: _fullLogData(log, originalTimestampStr),
        );

        log.isSynced = true;
        log.syncError = null;

        successCount++;
        needsSave = true;

        debugPrint("SYNC SUCCESS");
        debugPrint("Local Log ID   : ${log.id}");
        debugPrint("Backend Log ID : ${result.logId ?? 'unknown'}");
        debugPrint("Employee       : ${log.employeeName}");
        debugPrint("Punch Type     : ${result.punchType ?? 'unknown'}");
        debugPrint("Timestamp      : $originalTimestampStr");
      } on FaceAttendanceApiException catch (e) {
        log.syncError = e.toString();
        needsSave = true;

        debugPrint("SYNC FAILED");
        debugPrint("Local Log ID : ${log.id}");
        debugPrint("Employee     : ${log.employeeName}");
        debugPrint("Reason       : $e");
      } catch (e) {
        log.syncError = e.toString();
        needsSave = true;

        debugPrint("SYNC FAILED");
        debugPrint("Local Log ID : ${log.id}");
        debugPrint("Employee     : ${log.employeeName}");
        debugPrint("Reason       : $e");
      }
    }

    if (needsSave) {
      await saveLogs(logs);
    }

    debugPrint("");
    debugPrint("=======================================================");
    debugPrint("SYNC COMPLETED");
    debugPrint("Total Pending : ${pending.length}");
    debugPrint("Successfully Synced : $successCount");
    debugPrint("Failed : ${pending.length - successCount}");
    debugPrint("=======================================================");

    return successCount;
  }

  Future<void> clearLogs() async {
    _cache = [];
    try {
      final file = await _getLogFile();
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint('Error deleting local logs: $e');
    }
  }

  // ---------------------------------------------------------------------
  // Auto-sync: automatically push unsynced logs to the backend whenever
  // connectivity is available, with a periodic fallback timer.
  // ---------------------------------------------------------------------

  /// Call once (e.g. right after you build/obtain the authenticated
  /// [OdooFaceAttendanceClient]) to start automatically pushing unsynced
  /// logs whenever a connection is available.
  void startAutoSync(OdooFaceAttendanceClient client) {
    _syncClient = client;

    _connectivitySub?.cancel();
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final hasConnection = results.any((r) => r != ConnectivityResult.none);
      if (hasConnection) {
        _attemptSync();
      }
    });

    // Fallback: retry periodically in case a connectivity event is missed
    // or the OS reports "connected" but the network isn't actually reachable.
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _attemptSync(),
    );

    // Try once immediately too (e.g. app just started with a live connection).
    _attemptSync();
  }

  /// Call when the client/session is no longer valid (e.g. logout) or when
  /// the owning widget is disposed, to stop background sync attempts.
  void stopAutoSync() {
    _connectivitySub?.cancel();
    _connectivitySub = null;
    _syncTimer?.cancel();
    _syncTimer = null;
    _syncClient = null;
  }

  /// Manually trigger a sync attempt right now (e.g. from a "Sync now"
  /// button in the UI). Safe to call even if auto-sync isn't running,
  /// as long as you pass a client.
  Future<int> syncNow(OdooFaceAttendanceClient client) async {
    if (_isSyncing) return 0;
    _isSyncing = true;
    try {
      return await syncPendingLogs(client);
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> _attemptSync() async {
    if (_isSyncing || _syncClient == null) return;

    final logs = await getLogs();
    final hasPending = logs.any((log) => !log.isSynced);
    if (!hasPending) return;

    _isSyncing = true;
    try {
      final count = await syncPendingLogs(_syncClient!);
      if (count > 0) {
        debugPrint('Auto-sync: pushed $count pending log(s) to backend');
      }
    } catch (e) {
      debugPrint('Auto-sync attempt failed: $e');
    } finally {
      _isSyncing = false;
    }
  }
}
