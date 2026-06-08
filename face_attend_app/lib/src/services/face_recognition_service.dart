import 'dart:math';
import 'dart:io';
import 'dart:typed_data';

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class FaceRecognitionService {
  FaceRecognitionService()
      : _detector = FaceDetector(
          options: FaceDetectorOptions(
            enableClassification: true,
            enableLandmarks: true,
            performanceMode: FaceDetectorMode.accurate,
          ),
        );

  static const modelVersion = 'mobilefacenet-v1-dev-fallback';
  final FaceDetector _detector;

  Future<FaceEmbeddingResult> validateAndEmbed(String imagePath) async {
    final input = InputImage.fromFilePath(imagePath);
    final faces = await _detector.processImage(input);
    if (faces.isEmpty) {
      return FaceEmbeddingResult.failure('No face detected');
    }
    if (faces.length > 1) {
      return FaceEmbeddingResult.failure('Multiple faces detected');
    }

    final face = faces.single;
    final yaw = (face.headEulerAngleY ?? 0).abs();
    final pitch = (face.headEulerAngleX ?? 0).abs();
    if (yaw > 35 || pitch > 25) {
      return FaceEmbeddingResult.failure('Face angle is too high');
    }
    if (face.boundingBox.width < 120 || face.boundingBox.height < 120) {
      return FaceEmbeddingResult.failure('Move closer to the camera');
    }

    final bytes = Uint8List.fromList(await File(imagePath).readAsBytes());
    return FaceEmbeddingResult.success(
      embedding: _developmentEmbedding(bytes),
      qualityScore: _qualityScore(face),
    );
  }

  double compare(List<double> current, List<List<double>> enrolled) {
    if (enrolled.isEmpty) return 0;
    return enrolled.map((vector) => _cosineSimilarity(current, vector)).reduce(max);
  }

  Future<void> close() => _detector.close();

  List<double> _developmentEmbedding(Uint8List bytes) {
    final buckets = List<double>.filled(128, 0);
    for (var i = 0; i < bytes.length; i++) {
      buckets[i % buckets.length] += bytes[i] / 255.0;
    }
    final norm = sqrt(buckets.fold<double>(0, (sum, value) => sum + value * value));
    if (norm == 0) return buckets;
    return buckets.map((value) => value / norm).toList(growable: false);
  }

  double _cosineSimilarity(List<double> a, List<double> b) {
    final length = min(a.length, b.length);
    if (length == 0) return 0;
    var dot = 0.0;
    var normA = 0.0;
    var normB = 0.0;
    for (var i = 0; i < length; i++) {
      dot += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    if (normA == 0 || normB == 0) return 0;
    return dot / (sqrt(normA) * sqrt(normB));
  }

  double _qualityScore(Face face) {
    final sizeScore = min(face.boundingBox.width, face.boundingBox.height) / 260.0;
    final posePenalty = ((face.headEulerAngleY ?? 0).abs() + (face.headEulerAngleX ?? 0).abs()) / 100.0;
    return (sizeScore - posePenalty).clamp(0.0, 1.0);
  }
}

class FaceEmbeddingResult {
  const FaceEmbeddingResult._({
    required this.valid,
    this.embedding,
    this.qualityScore = 0,
    this.error,
  });

  final bool valid;
  final List<double>? embedding;
  final double qualityScore;
  final String? error;

  factory FaceEmbeddingResult.success({
    required List<double> embedding,
    required double qualityScore,
  }) {
    return FaceEmbeddingResult._(
      valid: true,
      embedding: embedding,
      qualityScore: qualityScore,
    );
  }

  factory FaceEmbeddingResult.failure(String error) {
    return FaceEmbeddingResult._(valid: false, error: error);
  }
}
