import 'dart:math';

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

  final FaceDetector _detector;

  Future<FaceValidationResult> validateImage(String imagePath) async {
    final input = InputImage.fromFilePath(imagePath);
    final faces = await _detector.processImage(input);
    if (faces.isEmpty) {
      return FaceValidationResult.failure('No face detected');
    }
    if (faces.length > 1) {
      return FaceValidationResult.failure('Multiple faces detected');
    }

    final face = faces.single;
    final yaw = (face.headEulerAngleY ?? 0).abs();
    final pitch = (face.headEulerAngleX ?? 0).abs();
    if (yaw > 35 || pitch > 25) {
      return FaceValidationResult.failure('Face angle is too high');
    }
    if (face.boundingBox.width < 120 || face.boundingBox.height < 120) {
      return FaceValidationResult.failure('Move closer to the camera');
    }

    return FaceValidationResult.success(qualityScore: _qualityScore(face));
  }

  Future<void> close() => _detector.close();

  double _qualityScore(Face face) {
    final sizeScore = min(face.boundingBox.width, face.boundingBox.height) / 260.0;
    final posePenalty = ((face.headEulerAngleY ?? 0).abs() + (face.headEulerAngleX ?? 0).abs()) / 100.0;
    return (sizeScore - posePenalty).clamp(0.0, 1.0);
  }
}

class FaceValidationResult {
  const FaceValidationResult._({
    required this.valid,
    this.qualityScore = 0,
    this.error,
  });

  final bool valid;
  final double qualityScore;
  final String? error;

  factory FaceValidationResult.success({
    required double qualityScore,
  }) {
    return FaceValidationResult._(
      valid: true,
      qualityScore: qualityScore,
    );
  }

  factory FaceValidationResult.failure(String error) {
    return FaceValidationResult._(valid: false, error: error);
  }
}
