import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'package:sqflite/sqflite.dart';

import '../api/odoo_face_attendance_client.dart';
import '../models/session.dart';
import 'database_helper.dart';
import 'face_recognition_service.dart';

class OnDeviceFaceMatcher {
  OnDeviceFaceMatcher({
    required OdooFaceAttendanceClient client,
    required FaceRecognitionService faceService,
  }) : _client = client,
       _faceService = faceService;

  static const double defaultThreshold = 0.60;
  static const double reviewThreshold = 0.50;
  static const double ambiguityMargin = 0.06;
  static const double adaptiveThreshold = 0.78;
  static const int maxVariantsPerEmployee = 5;
  static const String modelVersion = 'arcface-w600k-r50-align-v3';
  static const int embeddingDimensions = 512;

  final OdooFaceAttendanceClient _client;
  final FaceRecognitionService _faceService;
  LocalFaceIndex? _index;

  double get threshold => defaultThreshold;

  Future<FaceIndexSyncResult> sync() async {
    final stored = await LocalFaceIndexStore.read();
    ScannerEmployeeSync remote;
    try {
      remote = await _client.scannerEmployees(
        modelVersion: modelVersion,
        knownAvatarWriteDates: stored.avatarWriteDateMap,
      );
    } catch (e) {
      if (stored.records.isNotEmpty) {
        debugPrint('FaceAttend sync: network error ($e), using cached embeddings.');
        _index = stored;
        return FaceIndexSyncResult(
          indexedEmployees: stored.records.length,
          failures: ['Offline mode: Using cached employee list. ($e)'],
        );
      } else {
        rethrow;
      }
    }
    final effectiveModelVersion = remote.modelVersion == modelVersion
        ? remote.modelVersion
        : modelVersion;
    final records = <LocalFaceRecord>[];
    final failures = <String>[];
    debugPrint(
      'FaceAttend sync: remote=${remote.employees.length} '
      'model=${remote.modelVersion} effective=$effectiveModelVersion '
      'threshold=${remote.threshold}',
    );

    final unsynced = <ScannerEmployee>[];
    for (final employee in remote.employees.where((item) => item.faceEnabled)) {
      final cached = stored.recordFor(employee.id);
      if (cached != null &&
          stored.modelVersion == effectiveModelVersion &&
          cached.avatarWriteDate == employee.avatarWriteDate &&
          cached.primaryEmbedding.length == embeddingDimensions &&
          cached.primaryEmbedding.isNotEmpty) {
        records.add(cached.copyWith(name: employee.name));
      } else {
        unsynced.add(employee);
      }
    }

    if (unsynced.isNotEmpty) {
      // Process unsynced employees using a concurrency pool to speed up embedding computation
      const concurrency = 4;
      var index = 0;

      Future<void> worker() async {
        while (true) {
          final myIndex = index++;
          if (myIndex >= unsynced.length) break;

          final employee = unsynced[myIndex];
          if (employee.avatar.isEmpty) {
            failures.add('${employee.name}: missing avatar');
            continue;
          }

          try {
            final avatarBytes = base64Decode(employee.avatar);
            final embedding = await _faceService.embedImageBytes(avatarBytes);
            if (!embedding.valid || embedding.embedding == null) {
              failures.add(
                '${employee.name}: ${embedding.error ?? 'invalid avatar'}',
              );
              continue;
            }
            records.add(
              LocalFaceRecord(
                employeeId: employee.id,
                employeeName: employee.name,
                department: employee.department,
                avatarWriteDate: employee.avatarWriteDate,
                primaryEmbedding: embedding.embedding!.toList(),
                adaptiveEmbeddings: const [],
              ),
            );
            debugPrint(
              'FaceAttend sync indexed ${employee.id} ${employee.name} '
              'dim=${embedding.embedding!.length}',
            );
          } catch (error) {
            failures.add('${employee.name}: $error');
            debugPrint(
              'FaceAttend sync failed ${employee.id} ${employee.name}: $error',
            );
          }
        }
      }

      final workers = List.generate(concurrency, (_) => worker());
      await Future.wait(workers);
    }

    final index = LocalFaceIndex(
      modelVersion: effectiveModelVersion,
      threshold: defaultThreshold,
      syncedAt: DateTime.now(),
      records: records,
    );
    await LocalFaceIndexStore.write(index);
    _index = index;
    debugPrint(
      'FaceAttend sync complete: indexed=${records.length} '
      'failures=${failures.length}',
    );
    return FaceIndexSyncResult(
      indexedEmployees: records.length,
      failures: failures,
    );
  }

  Future<LocalFaceIndex> readyIndex() async {
    final index = _index ?? await LocalFaceIndexStore.read();
    _index = index;
    return index;
  }

  Future<LocalFaceMatchResult> matchImagePath(String imagePath) async {
    final index = await readyIndex();
    if (index.records.isEmpty) {
      return LocalFaceMatchResult.rejected(
        confidence: 0,
        threshold: index.threshold,
        reason: 'no_registered_embeddings',
      );
    }

    final embeddingResult = await _faceService.embedImagePath(imagePath);
    if (!embeddingResult.valid || embeddingResult.embedding == null) {
      return LocalFaceMatchResult.rejected(
        confidence: 0,
        threshold: index.threshold,
        reason: _reasonForFaceError(embeddingResult.error),
      );
    }

    final query = embeddingResult.embedding!;
    final candidates = <_Candidate>[];
    for (final record in index.records) {
      candidates.add(
        _Candidate(
          record: record,
          source: 'avatar_primary',
          score: _cosine(query, record.primaryVector),
        ),
      );
      for (var i = 0; i < record.adaptiveEmbeddings.length; i++) {
        candidates.add(
          _Candidate(
            record: record,
            source: 'adaptive_scan',
            score: _cosine(
              query,
              Float32List.fromList(record.adaptiveEmbeddings[i]),
            ),
          ),
        );
      }
    }
    candidates.sort((a, b) => b.score.compareTo(a.score));
    final best = candidates.first;
    final secondBestDifferent = candidates
        .where(
          (candidate) => candidate.record.employeeId != best.record.employeeId,
        )
        .cast<_Candidate?>()
        .firstWhere((candidate) => candidate != null, orElse: () => null);
    final secondScore = secondBestDifferent?.score;
    final threshold = defaultThreshold;
    debugPrint(
      'FaceAttend match: best=${best.record.employeeId} '
      '${best.record.employeeName} score=${best.score.toStringAsFixed(4)} '
      'second=${secondScore?.toStringAsFixed(4) ?? '-'} '
      'threshold=$threshold source=${best.source}',
    );

    if (secondScore != null && best.score - secondScore < ambiguityMargin) {
      return LocalFaceMatchResult.rejected(
        confidence: best.score,
        threshold: threshold,
        employeeId: best.record.employeeId,
        employeeName: best.record.employeeName,
        reason: 'ambiguous_match',
        secondBestConfidence: secondScore,
        embeddingSource: best.source,
        needsReview: best.score >= reviewThreshold,
      );
    }

    if (best.score < threshold) {
      return LocalFaceMatchResult.rejected(
        confidence: best.score,
        threshold: threshold,
        employeeId: best.record.employeeId,
        employeeName: best.record.employeeName,
        reason: best.score >= reviewThreshold
            ? 'needs_review'
            : 'below_threshold',
        secondBestConfidence: secondScore,
        embeddingSource: best.source,
        needsReview: best.score >= reviewThreshold,
      );
    }

    if (best.score >= adaptiveThreshold) {
      await _addAdaptiveEmbedding(best.record.employeeId, query);
    }

    return LocalFaceMatchResult.accepted(
      employeeId: best.record.employeeId,
      employeeName: best.record.employeeName,
      confidence: best.score,
      threshold: threshold,
      secondBestConfidence: secondScore,
      embeddingSource: best.source,
      livenessScore: embeddingResult.qualityScore,
    );
  }

  Future<void> _addAdaptiveEmbedding(
    int employeeId,
    Float32List embedding,
  ) async {
    final index = await readyIndex();
    final records = index.records.map((record) {
      if (record.employeeId != employeeId) return record;
      final variants = [
        embedding.toList(),
        ...record.adaptiveEmbeddings,
      ].take(maxVariantsPerEmployee - 1).toList();
      return record.copyWith(adaptiveEmbeddings: variants);
    }).toList();
    final updated = index.copyWith(records: records);
    _index = updated;
    await LocalFaceIndexStore.write(updated);
  }

  static double _cosine(Float32List a, Float32List b) {
    if (a.length != b.length || a.isEmpty) return 0;
    var dot = 0.0;
    var normA = 0.0;
    var normB = 0.0;
    for (var i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    if (normA <= 0 || normB <= 0) return 0;
    return dot / (math.sqrt(normA) * math.sqrt(normB));
  }

  static String _reasonForFaceError(String? error) {
    switch (error) {
      case 'No face detected':
        return 'no_face_detected';
      case 'Multiple faces detected':
        return 'multiple_faces_detected';
      case 'Move closer to the camera':
        return 'face_too_small';
      case 'Move slightly back':
        return 'face_too_large';
      default:
        if (error?.startsWith('ArcFace embedding failed') == true) {
          return 'arcface_embedding_failed';
        }
        return error ?? 'face_not_clear';
    }
  }
}

class LocalFaceIndexStore {
  static const _fileName = 'face_attend_local_embeddings.json';

  static Future<LocalFaceIndex> read() async {
    try {
      await DatabaseHelper.instance.migrateLegacyFilesIfNeeded();
      final records = await DatabaseHelper.instance.getFaceRecords();
      if (records.isNotEmpty) {
        final faceRecords = records.map((r) => LocalFaceRecord.fromJson({
          'employee_id': r['employee_id'],
          'employee_name': r['employee_name'],
          'department': r['department'],
          'avatar_write_date': r['avatar_write_date'],
          'primary_embedding': r['primary_embedding'],
          'adaptive_embeddings': r['adaptive_embeddings'],
        })).toList();
        return LocalFaceIndex(
          modelVersion: OnDeviceFaceMatcher.modelVersion,
          threshold: OnDeviceFaceMatcher.defaultThreshold,
          syncedAt: DateTime.now(),
          records: faceRecords,
        );
      }

      // JSON Fallback
      final directory = await getApplicationSupportDirectory();
      final file = File('${directory.path}/$_fileName');
      if (!await file.exists()) return LocalFaceIndex.empty();
      final payload =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return LocalFaceIndex.fromJson(payload);
    } catch (_) {
      return LocalFaceIndex.empty();
    }
  }

  static Future<void> write(LocalFaceIndex index) async {
    try {
      // 1. Save to SQLite inside a transaction to ensure atomicity and cleanup obsolete records
      final db = await DatabaseHelper.instance.database;
      await db.transaction((txn) async {
        if (index.records.isEmpty) {
          await txn.delete('face_embeddings');
        } else {
          final ids = index.records.map((r) => r.employeeId).toList();
          final placeholders = List.filled(ids.length, '?').join(',');
          await txn.delete(
            'face_embeddings',
            where: 'employee_id NOT IN ($placeholders)',
            whereArgs: ids,
          );
        }

        for (final rec in index.records) {
          await txn.insert(
            'face_embeddings',
            {
              'employee_id': rec.employeeId,
              'employee_name': rec.employeeName,
              'department': rec.department,
              'avatar_write_date': rec.avatarWriteDate,
              'primary_embedding_json': jsonEncode(rec.primaryEmbedding),
              'adaptive_embeddings_json': jsonEncode(rec.adaptiveEmbeddings),
              'updated_at': DateTime.now().toIso8601String(),
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      });

      // 2. JSON Fallback
      final directory = await getApplicationSupportDirectory();
      final file = File('${directory.path}/$_fileName');
      await file.writeAsString(jsonEncode(index.toJson()));
    } catch (e) {
      debugPrint('Error writing LocalFaceIndex to SQLite/JSON: $e');
    }
  }
}


class LocalFaceIndex {
  const LocalFaceIndex({
    required this.modelVersion,
    required this.threshold,
    required this.syncedAt,
    required this.records,
  });

  final String modelVersion;
  final double threshold;
  final DateTime syncedAt;
  final List<LocalFaceRecord> records;

  factory LocalFaceIndex.empty() {
    return LocalFaceIndex(
      modelVersion: OnDeviceFaceMatcher.modelVersion,
      threshold: OnDeviceFaceMatcher.defaultThreshold,
      syncedAt: DateTime.fromMillisecondsSinceEpoch(0),
      records: const [],
    );
  }

  factory LocalFaceIndex.fromJson(Map<String, dynamic> json) {
    return LocalFaceIndex(
      modelVersion:
          json['model_version'] as String? ?? OnDeviceFaceMatcher.modelVersion,
      threshold:
          (json['threshold'] as num? ?? OnDeviceFaceMatcher.defaultThreshold)
              .toDouble(),
      syncedAt:
          DateTime.tryParse(json['synced_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      records: (json['records'] as List<dynamic>? ?? [])
          .map((item) => LocalFaceRecord.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }

  LocalFaceRecord? recordFor(int employeeId) {
    for (final record in records) {
      if (record.employeeId == employeeId) return record;
    }
    return null;
  }

  Map<int, String> get avatarWriteDateMap => {
    for (final record in records) record.employeeId: record.avatarWriteDate,
  };

  LocalFaceIndex copyWith({List<LocalFaceRecord>? records}) {
    return LocalFaceIndex(
      modelVersion: modelVersion,
      threshold: threshold,
      syncedAt: syncedAt,
      records: records ?? this.records,
    );
  }

  Map<String, dynamic> toJson() => {
    'model_version': modelVersion,
    'threshold': threshold,
    'synced_at': syncedAt.toIso8601String(),
    'records': records.map((record) => record.toJson()).toList(),
  };
}

class LocalFaceRecord {
  const LocalFaceRecord({
    required this.employeeId,
    required this.employeeName,
    required this.avatarWriteDate,
    required this.primaryEmbedding,
    required this.adaptiveEmbeddings,
    this.department,
  });

  final int employeeId;
  final String employeeName;
  final String? department;
  final String avatarWriteDate;
  final List<double> primaryEmbedding;
  final List<List<double>> adaptiveEmbeddings;

  Float32List get primaryVector => Float32List.fromList(primaryEmbedding);

  factory LocalFaceRecord.fromJson(Map<String, dynamic> json) {
    return LocalFaceRecord(
      employeeId: json['employee_id'] as int,
      employeeName: json['employee_name'] as String,
      department: json['department'] as String?,
      avatarWriteDate: json['avatar_write_date'] as String? ?? '',
      primaryEmbedding: (json['primary_embedding'] as List<dynamic>? ?? [])
          .map((value) => (value as num).toDouble())
          .toList(),
      adaptiveEmbeddings: (json['adaptive_embeddings'] as List<dynamic>? ?? [])
          .map(
            (embedding) => (embedding as List<dynamic>)
                .map((value) => (value as num).toDouble())
                .toList(),
          )
          .toList(),
    );
  }

  LocalFaceRecord copyWith({
    String? name,
    List<List<double>>? adaptiveEmbeddings,
  }) {
    return LocalFaceRecord(
      employeeId: employeeId,
      employeeName: name ?? employeeName,
      department: department,
      avatarWriteDate: avatarWriteDate,
      primaryEmbedding: primaryEmbedding,
      adaptiveEmbeddings: adaptiveEmbeddings ?? this.adaptiveEmbeddings,
    );
  }

  Map<String, dynamic> toJson() => {
    'employee_id': employeeId,
    'employee_name': employeeName,
    'department': department,
    'avatar_write_date': avatarWriteDate,
    'primary_embedding': primaryEmbedding,
    'adaptive_embeddings': adaptiveEmbeddings,
  };
}

class LocalFaceMatchResult {
  const LocalFaceMatchResult({
    required this.matched,
    required this.confidence,
    required this.threshold,
    this.employeeId,
    this.employeeName,
    this.reason,
    this.secondBestConfidence,
    this.embeddingSource,
    this.needsReview = false,
    this.livenessPassed = true,
    this.livenessScore,
  });

  final bool matched;
  final double confidence;
  final double threshold;
  final int? employeeId;
  final String? employeeName;
  final String? reason;
  final double? secondBestConfidence;
  final String? embeddingSource;
  final bool needsReview;
  final bool livenessPassed;
  final double? livenessScore;

  factory LocalFaceMatchResult.accepted({
    required int employeeId,
    required String employeeName,
    required double confidence,
    required double threshold,
    double? secondBestConfidence,
    String? embeddingSource,
    double? livenessScore,
  }) {
    return LocalFaceMatchResult(
      matched: true,
      employeeId: employeeId,
      employeeName: employeeName,
      confidence: confidence,
      threshold: threshold,
      secondBestConfidence: secondBestConfidence,
      embeddingSource: embeddingSource,
      livenessScore: livenessScore,
    );
  }

  factory LocalFaceMatchResult.rejected({
    required double confidence,
    required double threshold,
    String? reason,
    int? employeeId,
    String? employeeName,
    double? secondBestConfidence,
    String? embeddingSource,
    bool needsReview = false,
    bool livenessPassed = true,
  }) {
    return LocalFaceMatchResult(
      matched: false,
      employeeId: employeeId,
      employeeName: employeeName,
      confidence: confidence,
      threshold: threshold,
      reason: reason,
      secondBestConfidence: secondBestConfidence,
      embeddingSource: embeddingSource,
      needsReview: needsReview,
      livenessPassed: livenessPassed,
    );
  }
}

class FaceIndexSyncResult {
  const FaceIndexSyncResult({
    required this.indexedEmployees,
    required this.failures,
  });

  final int indexedEmployees;
  final List<String> failures;
}

class _Candidate {
  const _Candidate({
    required this.record,
    required this.source,
    required this.score,
  });

  final LocalFaceRecord record;
  final String source;
  final double score;
}
