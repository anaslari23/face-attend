import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:face_detection_tflite/face_detection_tflite.dart' as mp;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'arcface_embedding_service.dart';

class FaceRecognitionService {
  mp.FaceDetector? _detector;
  final _arcFace = ArcFaceEmbeddingService();

  Future<void> initialize() async {
    if (_detector?.isReady == true) return;
    _detector = await mp.FaceDetector.create(
      model: mp.FaceDetectionModel.frontCamera,
    );
  }

  Future<FaceValidationResult> validateImage(String imagePath) async {
    final detector = await _readyDetector();
    final faces = await detector.detectFacesFromFilepath(
      imagePath,
      mode: mp.FaceDetectionMode.fast,
    );
    return _validateFaces(faces);
  }

  Future<FaceEmbeddingResult> embedImagePath(String imagePath, {bool isLiveCapture = true}) async {
    final bytes = await File(imagePath).readAsBytes();
    return embedImageBytes(bytes, isLiveCapture: isLiveCapture);
  }

  Future<FaceEmbeddingResult> embedImageBytes(Uint8List imageBytes, {bool isLiveCapture = false, mp.Face? knownFace, Size? knownImageSize}) async {
    mp.Face? faceToUse = knownFace;
    Size resolvedImageSize = knownImageSize ?? const Size(0, 0);

    if (faceToUse != null) {
      // Use the pre-computed face from stability tracking — skip re-detection.
      final validation = _validateSingleFace(faceToUse, resolvedImageSize);
      if (!validation.valid) {
        return FaceEmbeddingResult.failure(
          validation.error ?? 'Face not clear',
          boundingBox: validation.boundingBox,
          imageSize: validation.imageSize,
        );
      }
    } else {
      // Fallback: detect face from image bytes.
      final detector = await _readyDetector();
      final faces = await detector.detectFacesFromBytes(
        imageBytes,
        mode: mp.FaceDetectionMode.full,
      );
      final validation = _validateFaces(faces, isLiveCapture: isLiveCapture);
      if (!validation.valid) {
        return FaceEmbeddingResult.failure(
          validation.error ?? 'Face not clear',
          boundingBox: validation.boundingBox,
          imageSize: validation.imageSize,
        );
      }
      faceToUse = faces.single;
      resolvedImageSize = validation.imageSize ?? resolvedImageSize;
    }

    final Float32List embedding;
    try {
      embedding = await _arcFace.embed(
        imageBytes: imageBytes,
        face: faceToUse,
      );
    } catch (error) {
      return FaceEmbeddingResult.failure(
        'ArcFace embedding failed: $error',
        boundingBox: Rect.fromLTRB(faceToUse.boundingBox.left, faceToUse.boundingBox.top, faceToUse.boundingBox.right, faceToUse.boundingBox.bottom),
        imageSize: resolvedImageSize,
      );
    }
    final qualityScore = _qualityScore(
      Rect.fromLTRB(faceToUse.boundingBox.left, faceToUse.boundingBox.top, faceToUse.boundingBox.right, faceToUse.boundingBox.bottom),
      resolvedImageSize,
    );
    return FaceEmbeddingResult.success(
      embedding: embedding,
      qualityScore: qualityScore,
      boundingBox: Rect.fromLTRB(faceToUse.boundingBox.left, faceToUse.boundingBox.top, faceToUse.boundingBox.right, faceToUse.boundingBox.bottom),
      imageSize: resolvedImageSize,
    );
  }

  Future<FaceValidationResult> validateCameraImage({
    required CameraImage image,
    required CameraDescription camera,
    required DeviceOrientation deviceOrientation,
  }) async {
    final result = await detectCameraFaces(
      image: image,
      camera: camera,
      deviceOrientation: deviceOrientation,
    );
    if (result.faces.length == 1) {
      final face = result.faces.single;
      return FaceValidationResult.success(
        qualityScore: face.qualityScore,
        boundingBox: face.boundingBox,
        imageSize: result.imageSize,
      );
    }
    if (result.faces.length > 1) {
      return FaceValidationResult.failure(
        'Multiple faces detected',
        imageSize: result.imageSize,
      );
    }
    return FaceValidationResult.failure(
      result.message,
      imageSize: result.imageSize,
    );
  }

  Future<MultiFaceValidationResult> detectCameraFaces({
    required CameraImage image,
    required CameraDescription camera,
    required DeviceOrientation deviceOrientation,
  }) async {
    final detector = await _readyDetector();
    const maxDim = 640;
    final rotation = mp.rotationForFrame(
      width: image.width,
      height: image.height,
      sensorOrientation: camera.sensorOrientation,
      isFrontCamera: camera.lensDirection == CameraLensDirection.front,
      deviceOrientation: deviceOrientation,
    );
    final faces = await detector.detectFacesFromCameraImage(
      image,
      rotation: rotation,
      mode: mp.FaceDetectionMode.fast,
      maxDim: maxDim,
    );
    final imageSize = mp.detectionSize(
      width: image.width,
      height: image.height,
      rotation: rotation,
      maxDim: maxDim,
    );
    return _validateMultipleFaces(faces, imageSize: imageSize, strict: false);
  }

  /// Lightweight validation for real-time stability tracking.
  /// Only checks detection confidence and basic face size — skips
  /// expensive anatomical checks. Use at capture time for full validation.
  Future<FaceValidationResult> validateCaptureFace(mp.Face face, Size imageSize) async {
    return _validateSingleFace(face, imageSize);
  }

  Future<void> close() async {
    await _detector?.dispose();
    _detector = null;
  }

  Future<mp.FaceDetector> _readyDetector() async {
    await initialize();
    return _detector!;
  }

  FaceValidationResult _validateFaces(
    List<mp.Face> faces, {
    Size? imageSize,
    bool isLiveCapture = false,
  }) {
    if (faces.isEmpty) {
      return FaceValidationResult.failure('No face detected');
    }
    if (faces.length > 1) {
      return FaceValidationResult.failure('Multiple faces detected');
    }

    final face = faces.single;
    final box = face.boundingBox;
    final rect = Rect.fromLTRB(box.left, box.top, box.right, box.bottom);
    final resolvedImageSize = imageSize ?? face.originalSize;

    if (isLiveCapture) {
      final singleCheck = _validateSingleFace(face, resolvedImageSize);
      if (!singleCheck.valid) {
        return singleCheck;
      }
      return singleCheck;
    }

    final landmarks = face.landmarks;
    if (landmarks.leftEye == null ||
        landmarks.rightEye == null ||
        landmarks.noseTip == null ||
        landmarks.mouth == null) {
      return FaceValidationResult.failure('Face landmarks not detected');
    }

    // For static images/avatars, relax constraints (30x30 pixels min)
    const double minFaceSize = 30.0;
    if (rect.width < minFaceSize || rect.height < minFaceSize) {
      return FaceValidationResult.failure(
        'Face too small',
        boundingBox: rect,
        imageSize: resolvedImageSize,
      );
    }

    final qualityScore = _qualityScore(rect, resolvedImageSize);

    return FaceValidationResult.success(
      qualityScore: qualityScore,
      boundingBox: rect,
      imageSize: resolvedImageSize,
    );
  }

  MultiFaceValidationResult _validateMultipleFaces(
    List<mp.Face> faces, {
    required Size imageSize,
    bool strict = false,
  }) {
    if (faces.isEmpty) {
      return MultiFaceValidationResult(
        faces: const [],
        imageSize: imageSize,
        message: 'Looking for a face',
        rawFaceBoundingBox: null,
        isFaceFullyDirected: false,
      );
    }

    final rawBox = faces.first.boundingBox;
    final rawRect = Rect.fromLTRB(rawBox.left, rawBox.top, rawBox.right, rawBox.bottom);

    if (faces.length > 1) {
      return MultiFaceValidationResult(
        faces: const [],
        imageSize: imageSize,
        message: 'One person at a time',
        rawFaceBoundingBox: rawRect,
        isFaceFullyDirected: false,
      );
    }

    final validFaces = <DetectedFace>[];
    var rejectedMessage = 'Face not clear';
    for (final face in faces) {
      final validation = strict
          ? _validateSingleFace(face, imageSize)
          : _validateTracking(face, imageSize);
      if (validation.valid && validation.boundingBox != null) {
        validFaces.add(
          DetectedFace(
            face: face,
            boundingBox: validation.boundingBox!,
            qualityScore: validation.qualityScore,
            yawEstimate: _yawEstimate(face),
          ),
        );
      } else if (validation.error != null) {
        rejectedMessage = validation.error!;
      }
    }

    if (validFaces.isEmpty) {
      return MultiFaceValidationResult(
        faces: const [],
        imageSize: imageSize,
        message: rejectedMessage,
        rawFaceBoundingBox: rawRect,
        isFaceFullyDirected: false,
      );
    }
    return MultiFaceValidationResult(
      faces: validFaces,
      imageSize: imageSize,
      message: 'Hold still',
      rawFaceBoundingBox: validFaces.first.boundingBox,
      isFaceFullyDirected: true,
    );
  }

  FaceValidationResult _validateSingleFace(mp.Face face, Size imageSize) {
    // 1. Check detector confidence score (filter out partial/forehead/edge false positives)
    if (face.detectionData.score < 0.78) {
      return FaceValidationResult.failure('Looking for a face');
    }

    final landmarks = face.landmarks;
    if (landmarks.leftEye == null ||
        landmarks.rightEye == null ||
        landmarks.noseTip == null ||
        landmarks.mouth == null) {
      return FaceValidationResult.failure('Face landmarks not detected');
    }

    final box = face.boundingBox;
    final rect = Rect.fromLTRB(box.left, box.top, box.right, box.bottom);

    // 2. Ensure full face is inside the camera frame with safety margin away from edges (not cut off)
    final marginX = imageSize.width * 0.08;
    final marginY = imageSize.height * 0.08;
    if (rect.left < marginX ||
        rect.right > imageSize.width - marginX ||
        rect.top < marginY ||
        rect.bottom > imageSize.height - marginY) {
      return FaceValidationResult.failure(
        'Keep your full face in the camera view',
        boundingBox: rect,
        imageSize: imageSize,
      );
    }

    // 3. Ensure all individual facial landmarks are safely inside the margins
    final leftEye = landmarks.leftEye!;
    final rightEye = landmarks.rightEye!;
    final noseTip = landmarks.noseTip!;
    final mouth = landmarks.mouth!;
    for (final pt in [leftEye, rightEye, noseTip, mouth]) {
      if (pt.x < marginX ||
          pt.x > imageSize.width - marginX ||
          pt.y < marginY ||
          pt.y > imageSize.height - marginY) {
        return FaceValidationResult.failure(
          'Keep your full face in the camera view',
          boundingBox: rect,
          imageSize: imageSize,
        );
      }
    }

    // 4. Ensure face proportions and aspect ratio (human face is taller than wide, not flat/partial)
    final aspectRatio = rect.width / rect.height;
    if (aspectRatio < 0.58 || aspectRatio > 1.25) {
      return FaceValidationResult.failure(
        'Keep your full face in the camera view',
        boundingBox: rect,
        imageSize: imageSize,
      );
    }

    // 5. Anatomical Vertical Feature Separation (Forehead -> Eyes -> Nose -> Mouth -> Chin):
    final eyeY = (leftEye.y + rightEye.y) / 2;

    // (a) Eyes must be well below the top of the box (verifies forehead is present)
    if (eyeY - rect.top < rect.height * 0.15) {
      return FaceValidationResult.failure(
        'Keep your full face in the camera view',
        boundingBox: rect,
        imageSize: imageSize,
      );
    }

    // (b) Eyes must not be too low in the box
    if (eyeY - rect.top > rect.height * 0.60) {
      return FaceValidationResult.failure(
        'Keep your full face in the camera view',
        boundingBox: rect,
        imageSize: imageSize,
      );
    }

    // (c) Nose must be clearly below eyes
    if (noseTip.y <= eyeY + rect.height * 0.07) {
      return FaceValidationResult.failure(
        'Keep your full face in the camera view',
        boundingBox: rect,
        imageSize: imageSize,
      );
    }

    // (d) Mouth must be clearly below nose
    if (mouth.y <= noseTip.y + rect.height * 0.07) {
      return FaceValidationResult.failure(
        'Keep your full face in the camera view',
        boundingBox: rect,
        imageSize: imageSize,
      );
    }

    // (e) Chin must have clearance below mouth
    if (rect.bottom - mouth.y < rect.height * 0.08) {
      return FaceValidationResult.failure(
        'Keep your full face in the camera view',
        boundingBox: rect,
        imageSize: imageSize,
      );
    }

    // (f) Eye-to-mouth vertical span must be substantial (at least 28% of face height)
    if ((mouth.y - eyeY) < rect.height * 0.28) {
      return FaceValidationResult.failure(
        'Keep your full face in the camera view',
        boundingBox: rect,
        imageSize: imageSize,
      );
    }

    // 6. Inter-ocular distance (eyes must be separated appropriately for a full face)
    final eyeDistance = (leftEye.x - rightEye.x).abs();
    if (eyeDistance < rect.width * 0.22 || eyeDistance > rect.width * 0.50) {
      return FaceValidationResult.failure(
        'Keep your full face in the camera view',
        boundingBox: rect,
        imageSize: imageSize,
      );
    }

    // 7. Ear tragions (verify lateral face extent if available)
    final leftTragion = landmarks.leftEyeTragion;
    final rightTragion = landmarks.rightEyeTragion;
    if (leftTragion != null && rightTragion != null) {
      final tragionDistance = (leftTragion.x - rightTragion.x).abs();
      if (tragionDistance < rect.width * 0.40) {
        return FaceValidationResult.failure(
          'Keep your full face in the camera view',
          boundingBox: rect,
          imageSize: imageSize,
        );
      }
    }

    // 8. Ensure face size is adequate and not too far or too close
    final shortSide = min(imageSize.width, imageSize.height);
    final minFaceSize = shortSide * 0.28;
    if (rect.width < minFaceSize || rect.height < minFaceSize) {
      return FaceValidationResult.failure(
        'Move closer to the camera',
        boundingBox: rect,
        imageSize: imageSize,
      );
    }
    final maxFaceSize = shortSide * 0.85;
    if (rect.width > maxFaceSize || rect.height > maxFaceSize) {
      return FaceValidationResult.failure(
        'Move slightly back',
        boundingBox: rect,
        imageSize: imageSize,
      );
    }

    // 9. Ensure the face is directed straight at the camera (not turned away)
    final yaw = _yawEstimate(face);
    if (yaw.abs() > 0.18) {
      return FaceValidationResult.failure(
        'Look straight at the camera',
        boundingBox: rect,
        imageSize: imageSize,
      );
    }

    // 10. Ensure head is not excessively tilted sideways
    final eyeDy = (leftEye.y - rightEye.y).abs();
    if (eyeDistance > 0 && (eyeDy / eyeDistance) > 0.25) {
      return FaceValidationResult.failure(
        'Keep your head straight',
        boundingBox: rect,
        imageSize: imageSize,
      );
    }

    // 11. Check quality score
    final qualityScore = _qualityScore(rect, imageSize);
    if (qualityScore < 0.35) {
      return FaceValidationResult.failure(
        'Face not clear',
        boundingBox: rect,
        imageSize: imageSize,
      );
    }

    return FaceValidationResult.success(
      qualityScore: qualityScore,
      boundingBox: rect,
      imageSize: imageSize,
    );
  }

  double _qualityScore(Rect boundingBox, Size imageSize) {
    final double baseScore = 0.85;
    final double shortSide = min(imageSize.width, imageSize.height);
    final double faceSize = min(boundingBox.width, boundingBox.height);
    final double sizeDeviation = (faceSize / shortSide - 0.40).abs();
    return (baseScore - sizeDeviation).clamp(0.5, 1.0);
  }

  double _yawEstimate(mp.Face face) {
    final landmarks = face.landmarks;
    final leftEye = landmarks.leftEye;
    final rightEye = landmarks.rightEye;
    final nose = landmarks.noseTip;
    if (leftEye == null || rightEye == null || nose == null) return 0;
    final eyeCenterX = (leftEye.x + rightEye.x) / 2;
    final eyeDistance = (leftEye.x - rightEye.x).abs();
    if (eyeDistance <= 0) return 0;
    return ((nose.x - eyeCenterX) / eyeDistance).clamp(-1.0, 1.0);
  }

  // Lightweight validation for real-time stability tracking.
  // Only 3 fast checks — the full 11-point structural validation
  // runs once at capture time via _validateCapture().
  FaceValidationResult _validateTracking(mp.Face face, Size imageSize) {
    if (face.detectionData.score < 0.60) {
      return FaceValidationResult.failure('Looking for a face');
    }

    final box = face.boundingBox;
    final rect = Rect.fromLTRB(box.left, box.top, box.right, box.bottom);

    final shortSide = min(imageSize.width, imageSize.height);
    final minFaceSize = shortSide * 0.20;
    if (rect.width < minFaceSize || rect.height < minFaceSize) {
      return FaceValidationResult.failure('Move closer to the camera');
    }

    return FaceValidationResult.success(
      qualityScore: face.detectionData.score.toDouble(),
      boundingBox: rect,
      imageSize: imageSize,
    );
  }
}

class FaceValidationResult {
  const FaceValidationResult._({
    required this.valid,
    this.qualityScore = 0,
    this.error,
    this.boundingBox,
    this.imageSize,
  });

  final bool valid;
  final double qualityScore;
  final String? error;
  final Rect? boundingBox;
  final Size? imageSize;

  factory FaceValidationResult.success({
    required double qualityScore,
    Rect? boundingBox,
    Size? imageSize,
  }) {
    return FaceValidationResult._(
      valid: true,
      qualityScore: qualityScore,
      boundingBox: boundingBox,
      imageSize: imageSize,
    );
  }

  factory FaceValidationResult.failure(
    String error, {
    Rect? boundingBox,
    Size? imageSize,
  }) {
    return FaceValidationResult._(
      valid: false,
      error: error,
      boundingBox: boundingBox,
      imageSize: imageSize,
    );
  }
}

class FaceEmbeddingResult {
  const FaceEmbeddingResult._({
    required this.valid,
    required this.qualityScore,
    this.embedding,
    this.error,
    this.boundingBox,
    this.imageSize,
  });

  final bool valid;
  final double qualityScore;
  final Float32List? embedding;
  final String? error;
  final Rect? boundingBox;
  final Size? imageSize;

  factory FaceEmbeddingResult.success({
    required Float32List embedding,
    required double qualityScore,
    Rect? boundingBox,
    Size? imageSize,
  }) {
    return FaceEmbeddingResult._(
      valid: true,
      qualityScore: qualityScore,
      embedding: embedding,
      boundingBox: boundingBox,
      imageSize: imageSize,
    );
  }

  factory FaceEmbeddingResult.failure(
    String error, {
    Rect? boundingBox,
    Size? imageSize,
  }) {
    return FaceEmbeddingResult._(
      valid: false,
      qualityScore: 0,
      error: error,
      boundingBox: boundingBox,
      imageSize: imageSize,
    );
  }
}

class MultiFaceValidationResult {
  const MultiFaceValidationResult({
    required this.faces,
    required this.imageSize,
    required this.message,
    this.rawFaceBoundingBox,
    this.isFaceFullyDirected = false,
  });

  final List<DetectedFace> faces;
  final Size imageSize;
  final String message;
  final Rect? rawFaceBoundingBox;
  final bool isFaceFullyDirected;
}

class DetectedFace {
  const DetectedFace({
    required this.face,
    required this.boundingBox,
    required this.qualityScore,
    required this.yawEstimate,
  });

  final mp.Face face;
  final Rect boundingBox;
  final double qualityScore;
  final double yawEstimate;
}
