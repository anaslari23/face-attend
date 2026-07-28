import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path_provider/path_provider.dart';

import '../api/odoo_face_attendance_client.dart';
import '../models/session.dart';
import 'face_recognition_service.dart';

class OnDeviceFaceMatcher {
  OnDeviceFaceMatcher({
    required OdooFaceAttendanceClient client,
    required FaceRecognitionService faceService,
  }) : _client = client,
       _faceService = faceService;

  static const double defaultThreshold = 0.70;
  static const double reviewThreshold = 0.60;
  static const double ambiguityMargin = 0.06;
  static const double adaptiveThreshold = 0.78;
  static const int maxVariantsPerEmployee = 5;
  static const String modelVersion = 'arcface-w600k-r50-align-v3';
  static const int embeddingDimensions = 512;

  final OdooFaceAttendanceClient _client;
  final FaceRecognitionService _faceService;
  LocalFaceIndex? _index;

  Future<FaceIndexSyncResult> sync() async {
    final stored = await LocalFaceIndexStore.read();
    try {
      final manifest = await _client.scannerIndexManifest(
        since: stored.revision,
      );
      if (manifest == null) {
        _index = stored;
        return FaceIndexSyncResult(
          indexedEmployees: stored.records.length,
          failures: const [],
        );
      }
      if (manifest.modelVersion != modelVersion ||
          manifest.dimensions != embeddingDimensions) {
        throw StateError(
          'Scanner index model is incompatible with this app version.',
        );
      }

      final records = <int, LocalFaceRecord>{
        if (stored.modelVersion == manifest.modelVersion)
          for (final record in stored.records) record.employeeId: record,
      };
      final enabled = <ScannerIndexChange>[];
      for (final change in manifest.changes) {
        if (!change.enabled) {
          records.remove(change.employeeId);
        } else {
          enabled.add(change);
        }
      }
      for (var start = 0; start < enabled.length; start += 250) {
        final batch = enabled.skip(start).take(250).toList();
        final vectors = _decodeChunk(
          await _client.scannerIndexChunk(
            batch.map((item) => item.employeeId).toList(),
          ),
        );
        if (vectors.length != batch.length) {
          throw StateError(
            'Scanner index chunk did not contain every requested employee.',
          );
        }
        for (final change in batch) {
          final vector = vectors[change.employeeId];
          if (vector == null) {
            throw StateError(
              'Scanner index chunk is missing employee ${change.employeeId}.',
            );
          }
          records[change.employeeId] = LocalFaceRecord(
            employeeId: change.employeeId,
            employeeName: change.name ?? 'Employee ${change.employeeId}',
            department: change.department,
            avatarWriteDate: change.revision.toString(),
            primaryEmbedding: vector.toList(),
            adaptiveEmbeddings: const [],
          );
        }
      }
      final index = LocalFaceIndex(
        modelVersion: manifest.modelVersion,
        threshold: manifest.threshold,
        revision: manifest.revision,
        syncedAt: DateTime.now(),
        records: records.values.toList()
          ..sort((a, b) => a.employeeId.compareTo(b.employeeId)),
      );
      if (index.records.isEmpty && stored.records.isEmpty) {
        throw StateError('Employee index is preparing. Try again shortly.');
      }
      await LocalFaceIndexStore.write(index);
      _index = index;
      return FaceIndexSyncResult(
        indexedEmployees: index.records.length,
        failures: const [],
      );
    } catch (e) {
      if (stored.records.isNotEmpty) {
        _index = stored;
        return FaceIndexSyncResult(
          indexedEmployees: stored.records.length,
          failures: ['Offline mode: Using cached employee list. ($e)'],
        );
      } else {
        throw StateError('Employee index is unavailable. Try again shortly.');
      }
    }
  }

  Future<FaceIndexSyncResult> syncLegacyAvatars() async {
    final stored = await LocalFaceIndexStore.read();
    final remote = await _client.scannerEmployees(
      modelVersion: modelVersion,
      knownAvatarWriteDates: stored.avatarWriteDateMap,
    );
    final records = <LocalFaceRecord>[];
    final failures = <String>[];
    final pending = <ScannerEmployee>[];
    for (final employee in remote.employees.where((item) => item.faceEnabled)) {
      final cached = stored.recordFor(employee.id);
      if (cached != null &&
          cached.avatarWriteDate == employee.avatarWriteDate &&
          cached.primaryEmbedding.length == embeddingDimensions) {
        records.add(cached.copyWith(name: employee.name));
      } else {
        pending.add(employee);
      }
    }

    var next = 0;
    // ponytail: four on-device embeddings at once; use central templates for enterprise provisioning.
    Future<void> worker() async {
      while (next < pending.length) {
        final employee = pending[next++];
        if (employee.avatar.isEmpty) {
          failures.add('${employee.name}: missing avatar');
          continue;
        }
        try {
          final result = await _faceService.embedImageBytes(
            base64Decode(employee.avatar),
          );
          if (!result.valid || result.embedding == null) {
            failures.add(
              '${employee.name}: ${result.error ?? 'invalid avatar'}',
            );
            continue;
          }
          records.add(
            LocalFaceRecord(
              employeeId: employee.id,
              employeeName: employee.name,
              department: employee.department,
              avatarWriteDate: employee.avatarWriteDate,
              primaryEmbedding: result.embedding!.toList(),
              adaptiveEmbeddings: const [],
            ),
          );
        } catch (error) {
          failures.add('${employee.name}: $error');
        }
      }
    }

    await Future.wait(List.generate(4, (_) => worker()));
    final index = LocalFaceIndex(
      modelVersion: modelVersion,
      threshold: remote.threshold,
      revision: 0,
      syncedAt: DateTime.now(),
      records: records,
    );
    await LocalFaceIndexStore.write(index);
    _index = index;
    return FaceIndexSyncResult(
      indexedEmployees: records.length,
      failures: failures,
    );
  }

  static Map<int, Float32List> _decodeChunk(Uint8List bytes) {
    if (bytes.length < 8 ||
        String.fromCharCodes(bytes.sublist(0, 4)) != 'FAI1') {
      throw const FormatException('Invalid scanner index chunk.');
    }
    final data = ByteData.sublistView(bytes);
    final count = data.getUint32(4, Endian.big);
    const recordSize = 4 + embeddingDimensions * 4;
    if (bytes.length != 8 + count * recordSize) {
      throw const FormatException('Truncated scanner index chunk.');
    }
    final result = <int, Float32List>{};
    var offset = 8;
    for (var index = 0; index < count; index++) {
      final employeeId = data.getUint32(offset, Endian.big);
      offset += 4;
      final vector = Float32List(embeddingDimensions);
      var norm = 0.0;
      for (var dimension = 0; dimension < embeddingDimensions; dimension++) {
        vector[dimension] = data.getFloat32(offset, Endian.big);
        norm += vector[dimension] * vector[dimension];
        offset += 4;
      }
      if (!norm.isFinite || norm < 0.01) {
        throw const FormatException('Invalid scanner index embedding.');
      }
      result[employeeId] = vector;
    }
    return result;
  }

  @visibleForTesting
  static Map<int, Float32List> decodeChunkForTesting(Uint8List bytes) =>
      _decodeChunk(bytes);

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
    final threshold = index.threshold > 0 ? index.threshold : defaultThreshold;

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
  static const _fileName = 'face_attend_scanner_index.bin';

  static Future<LocalFaceIndex> read() async {
    try {
      final directory = await getApplicationSupportDirectory();
      final file = File('${directory.path}/$_fileName');
      if (!await file.exists()) return LocalFaceIndex.empty();
      return _decode(await file.readAsBytes());
    } catch (_) {
      return LocalFaceIndex.empty();
    }
  }

  static Future<void> write(LocalFaceIndex index) async {
    final directory = await getApplicationSupportDirectory();
    final file = File('${directory.path}/$_fileName');
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsBytes(_encode(index), flush: true);
    await temporary.rename(file.path);
  }

  static Uint8List _encode(LocalFaceIndex index) {
    final body = BytesBuilder(copy: false);
    _writeText(body, index.modelVersion);
    _writeU32(body, index.revision);
    _writeF64(body, index.threshold);
    _writeI64(body, index.syncedAt.millisecondsSinceEpoch);
    _writeU32(body, index.records.length);
    for (final record in index.records) {
      _writeU32(body, record.employeeId);
      _writeText(body, record.employeeName);
      _writeNullableText(body, record.department);
      _writeText(body, record.avatarWriteDate);
      if (record.adaptiveEmbeddings.length > 255) {
        throw StateError(
          'Too many adaptive templates for employee ${record.employeeId}.',
        );
      }
      body.addByte(record.adaptiveEmbeddings.length);
      _writeVector(body, record.primaryEmbedding);
      for (final vector in record.adaptiveEmbeddings) {
        _writeVector(body, vector);
      }
    }
    final payload = body.takeBytes();
    final result = BytesBuilder(copy: false)..add(utf8.encode('FAI2'));
    _writeU32(result, _checksum(payload));
    result.add(payload);
    return result.takeBytes();
  }

  @visibleForTesting
  static Uint8List encodeForTesting(LocalFaceIndex index) => _encode(index);

  static LocalFaceIndex _decode(Uint8List bytes) {
    if (bytes.length < 8 ||
        utf8.decode(bytes.sublist(0, 4), allowMalformed: true) != 'FAI2') {
      throw const FormatException('Unsupported scanner index format.');
    }
    final data = ByteData.sublistView(bytes);
    final expectedChecksum = data.getUint32(4, Endian.big);
    final payload = bytes.sublist(8);
    if (_checksum(payload) != expectedChecksum)
      throw const FormatException('Scanner index checksum failed.');
    var offset = 8;
    final model = _readText(bytes, data, offset);
    offset = model.$2;
    final revision = data.getUint32(offset, Endian.big);
    offset += 4;
    final threshold = data.getFloat64(offset, Endian.big);
    offset += 8;
    final syncedAt = DateTime.fromMillisecondsSinceEpoch(
      data.getInt64(offset, Endian.big),
    );
    offset += 8;
    final count = data.getUint32(offset, Endian.big);
    offset += 4;
    final records = <LocalFaceRecord>[];
    for (var item = 0; item < count; item++) {
      final employeeId = data.getUint32(offset, Endian.big);
      offset += 4;
      final name = _readText(bytes, data, offset);
      offset = name.$2;
      final department = _readNullableText(bytes, data, offset);
      offset = department.$2;
      final avatarDate = _readText(bytes, data, offset);
      offset = avatarDate.$2;
      final adaptiveCount = data.getUint8(offset++);
      final primary = _readVector(data, offset);
      offset += OnDeviceFaceMatcher.embeddingDimensions * 4;
      final adaptive = <List<double>>[];
      for (var variant = 0; variant < adaptiveCount; variant++) {
        adaptive.add(_readVector(data, offset));
        offset += OnDeviceFaceMatcher.embeddingDimensions * 4;
      }
      records.add(
        LocalFaceRecord(
          employeeId: employeeId,
          employeeName: name.$1,
          department: department.$1,
          avatarWriteDate: avatarDate.$1,
          primaryEmbedding: primary,
          adaptiveEmbeddings: adaptive,
        ),
      );
    }
    if (offset != bytes.length)
      throw const FormatException('Unexpected scanner index data.');
    return LocalFaceIndex(
      modelVersion: model.$1,
      threshold: threshold,
      revision: revision,
      syncedAt: syncedAt,
      records: records,
    );
  }

  @visibleForTesting
  static LocalFaceIndex decodeForTesting(Uint8List bytes) => _decode(bytes);

  static void _writeU32(BytesBuilder builder, int value) {
    final data = ByteData(4)..setUint32(0, value, Endian.big);
    builder.add(data.buffer.asUint8List());
  }

  static void _writeI64(BytesBuilder builder, int value) {
    final data = ByteData(8)..setInt64(0, value, Endian.big);
    builder.add(data.buffer.asUint8List());
  }

  static void _writeF64(BytesBuilder builder, double value) {
    final data = ByteData(8)..setFloat64(0, value, Endian.big);
    builder.add(data.buffer.asUint8List());
  }

  static void _writeText(BytesBuilder builder, String value) {
    final encoded = utf8.encode(value);
    if (encoded.length > 65534)
      throw const FormatException('Scanner index text is too long.');
    final data = ByteData(2)..setUint16(0, encoded.length, Endian.big);
    builder.add(data.buffer.asUint8List());
    builder.add(encoded);
  }

  static void _writeNullableText(BytesBuilder builder, String? value) {
    if (value == null) {
      final data = ByteData(2)..setUint16(0, 65535, Endian.big);
      builder.add(data.buffer.asUint8List());
    } else {
      _writeText(builder, value);
    }
  }

  static void _writeVector(BytesBuilder builder, List<double> vector) {
    if (vector.length != OnDeviceFaceMatcher.embeddingDimensions)
      throw const FormatException('Invalid embedding size.');
    final data = ByteData(vector.length * 4);
    for (var index = 0; index < vector.length; index++) {
      data.setFloat32(index * 4, vector[index], Endian.big);
    }
    builder.add(data.buffer.asUint8List());
  }

  static (String, int) _readText(Uint8List bytes, ByteData data, int offset) {
    if (offset + 2 > bytes.length)
      throw const FormatException('Truncated scanner index text.');
    final length = data.getUint16(offset, Endian.big);
    if (length == 65535 || offset + 2 + length > bytes.length)
      throw const FormatException('Invalid scanner index text.');
    return (
      utf8.decode(bytes.sublist(offset + 2, offset + 2 + length)),
      offset + 2 + length,
    );
  }

  static (String?, int) _readNullableText(
    Uint8List bytes,
    ByteData data,
    int offset,
  ) {
    if (offset + 2 > bytes.length)
      throw const FormatException('Truncated scanner index text.');
    if (data.getUint16(offset, Endian.big) == 65535) return (null, offset + 2);
    return _readText(bytes, data, offset);
  }

  static List<double> _readVector(ByteData data, int offset) {
    final vector = List<double>.filled(
      OnDeviceFaceMatcher.embeddingDimensions,
      0,
    );
    for (var index = 0; index < vector.length; index++) {
      vector[index] = data.getFloat32(offset + index * 4, Endian.big);
    }
    return vector;
  }

  static int _checksum(Uint8List bytes) {
    var hash = 0x811c9dc5;
    for (final byte in bytes) {
      hash = (hash ^ byte) * 0x01000193 & 0xffffffff;
    }
    return hash;
  }
}

class LocalFaceIndex {
  const LocalFaceIndex({
    required this.modelVersion,
    required this.threshold,
    required this.revision,
    required this.syncedAt,
    required this.records,
  });

  final String modelVersion;
  final double threshold;
  final int revision;
  final DateTime syncedAt;
  final List<LocalFaceRecord> records;

  factory LocalFaceIndex.empty() {
    return LocalFaceIndex(
      modelVersion: OnDeviceFaceMatcher.modelVersion,
      threshold: OnDeviceFaceMatcher.defaultThreshold,
      revision: 0,
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
      revision: (json['revision'] as num? ?? 0).toInt(),
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
      revision: revision,
      syncedAt: syncedAt,
      records: records ?? this.records,
    );
  }

  Map<String, dynamic> toJson() => {
    'model_version': modelVersion,
    'threshold': threshold,
    'revision': revision,
    'synced_at': syncedAt.toIso8601String(),
    'records': records.map((record) => record.toJson()).toList(),
  };
}

class LocalFaceRecord {
  LocalFaceRecord({
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

  late final Float32List primaryVector = Float32List.fromList(primaryEmbedding);

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
      livenessPassed: false,
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
