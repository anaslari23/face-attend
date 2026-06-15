import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../api/odoo_face_attendance_client.dart';

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
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
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

  Future<File> _getLogFile() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/$_fileName');
  }

  Future<List<LocalPunchLog>> getLogs() async {
    if (_cache != null) {
      return _cache!;
    }
    try {
      final file = await _getLogFile();
      if (!await file.exists()) {
        _cache = [];
        return _cache!;
      }
      final contents = await file.readAsString();
      final decoded = jsonDecode(contents) as List<dynamic>;
      _cache = decoded
          .map((item) => LocalPunchLog.fromJson(item as Map<String, dynamic>))
          .toList();
      // Sort with newest logs first
      _cache!.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return _cache!;
    } catch (e) {
      debugPrint('Error reading local logs: $e');
      _cache = [];
      return _cache!;
    }
  }

  Future<void> saveLogs(List<LocalPunchLog> logs) async {
    try {
      _cache = List.from(logs);
      _cache!.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      
      // Limit list size to avoid infinite storage growth
      if (_cache!.length > _maxLogCount) {
        _cache = _cache!.sublist(0, _maxLogCount);
      }

      final file = await _getLogFile();
      final jsonList = _cache!.map((log) => log.toJson()).toList();
      await file.writeAsString(jsonEncode(jsonList));
    } catch (e) {
      debugPrint('Error saving local logs: $e');
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

  Future<void> updateLogSyncStatus(String id, {required bool isSynced, String? syncError}) async {
    final logs = await getLogs();
    final index = logs.indexWhere((log) => log.id == id);
    if (index != -1) {
      logs[index].isSynced = isSynced;
      logs[index].syncError = syncError;
      await saveLogs(logs);
    }
  }

  Future<int> syncPendingLogs(OdooFaceAttendanceClient client) async {
    final logs = await getLogs();
    final pending = logs.where((log) => !log.isSynced).toList();
    if (pending.isEmpty) {
      return 0;
    }

    int successCount = 0;
    for (final log in pending) {
      try {
        final p = log.payload;
        // Inject original timestamp in ISO-8601 format
        final originalTimestampStr = log.timestamp.toIso8601String();
        
        await client.punch(
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
        );

        log.isSynced = true;
        log.syncError = null;
        successCount++;
      } catch (e) {
        log.syncError = e.toString();
        debugPrint('Failed to sync log ${log.id}: $e');
      }
    }

    if (successCount > 0) {
      await saveLogs(logs);
    }
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
}
