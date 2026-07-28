import 'dart:math' as math;
import 'dart:typed_data';

import 'package:face_attend_app/src/services/on_device_face_matcher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const employeeCount = int.fromEnvironment(
    'EMPLOYEE_COUNT',
    defaultValue: 1000,
  );
  const chunkSize = 250;

  test('scanner index benchmark ($employeeCount employees)', () {
    final vectors = _chunk(employeeCount);
    final chunks = <Uint8List>[
      for (var start = 0; start < employeeCount; start += chunkSize)
        _encodeChunk(
          vectors.sublist(start, math.min(start + chunkSize, employeeCount)),
        ),
    ];

    final decodeWatch = Stopwatch()..start();
    final records = <LocalFaceRecord>[];
    for (final chunk in chunks) {
      for (final entry in OnDeviceFaceMatcher.decodeChunkForTesting(
        chunk,
      ).entries) {
        records.add(
          LocalFaceRecord(
            employeeId: entry.key,
            employeeName: 'Employee ${entry.key}',
            avatarWriteDate: '1',
            primaryEmbedding: entry.value.toList(),
            adaptiveEmbeddings: const [],
          ),
        );
      }
    }
    decodeWatch.stop();

    final index = LocalFaceIndex(
      modelVersion: OnDeviceFaceMatcher.modelVersion,
      threshold: OnDeviceFaceMatcher.defaultThreshold,
      revision: 1,
      syncedAt: DateTime.now(),
      records: records,
    );
    final snapshotWatch = Stopwatch()..start();
    final snapshot = LocalFaceIndexStore.encodeForTesting(index);
    final restored = LocalFaceIndexStore.decodeForTesting(snapshot);
    snapshotWatch.stop();

    expect(restored.records, hasLength(employeeCount));
    expect(
      records.map((record) => record.employeeId).toSet(),
      hasLength(employeeCount),
    );
    // Keep the result visible in `flutter test` output for a real approved phone.
    // ignore: avoid_print
    print(
      'SCANNER_INDEX_BENCHMARK employees=$employeeCount '
      'transfer_bytes=${chunks.fold<int>(0, (sum, chunk) => sum + chunk.length)} '
      'snapshot_bytes=${snapshot.length} '
      'chunk_decode_ms=${decodeWatch.elapsedMilliseconds} '
      'snapshot_round_trip_ms=${snapshotWatch.elapsedMilliseconds}',
    );
  });
}

List<_Vector> _chunk(int count) {
  final value = 1 / math.sqrt(OnDeviceFaceMatcher.embeddingDimensions);
  return [
    for (var id = 1; id <= count; id++)
      _Vector(
        id,
        Float32List.fromList(
          List<double>.filled(OnDeviceFaceMatcher.embeddingDimensions, value),
        ),
      ),
  ];
}

Uint8List _encodeChunk(List<_Vector> vectors) {
  final bytes = Uint8List(
    8 + vectors.length * (4 + OnDeviceFaceMatcher.embeddingDimensions * 4),
  );
  bytes.setRange(0, 4, 'FAI1'.codeUnits);
  final data = ByteData.sublistView(bytes)
    ..setUint32(4, vectors.length, Endian.big);
  var offset = 8;
  for (final vector in vectors) {
    data.setUint32(offset, vector.employeeId, Endian.big);
    offset += 4;
    for (final value in vector.embedding) {
      data.setFloat32(offset, value, Endian.big);
      offset += 4;
    }
  }
  return bytes;
}

class _Vector {
  const _Vector(this.employeeId, this.embedding);

  final int employeeId;
  final Float32List embedding;
}
