import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:face_detection_tflite/face_detection_tflite.dart' as mp;
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

  Future<FaceEmbeddingResult> embedImagePath(String imagePath) async {
    final bytes = await File(imagePath).readAsBytes();
    return embedImageBytes(bytes);
  }

  Future<FaceEmbeddingResult> embedImageBytes(Uint8List imageBytes) async {
    final detector = await _readyDetector();
    final faces = await detector.detectFacesFromBytes(
      imageBytes,
      mode: mp.FaceDetectionMode.full,
    );
    final validation = _validateFaces(faces);
    if (!validation.valid) {
      return FaceEmbeddingResult.failure(
        validation.error ?? 'Face not clear',
        boundingBox: validation.boundingBox,
        imageSize: validation.imageSize,
      );
    }
    final Float32List embedding;
    try {
      embedding = await _arcFace.embed(
        imageBytes: imageBytes,
        face: faces.single,
      );
    } catch (error) {
      return FaceEmbeddingResult.failure(
        'ArcFace embedding failed: $error',
        boundingBox: validation.boundingBox,
        imageSize: validation.imageSize,
      );
    }
    return FaceEmbeddingResult.success(
      embedding: embedding,
      qualityScore: validation.qualityScore,
      boundingBox: validation.boundingBox,
      imageSize: validation.imageSize,
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
    return _validateMultipleFaces(faces, imageSize: imageSize);
  }

  Future<void> close() async {
    await _detector?.dispose();
    _detector = null;
  }

  Future<mp.FaceDetector> _readyDetector() async {
    await initialize();
    return _detector!;
  }

  FaceValidationResult _validateFaces(List<mp.Face> faces, {Size? imageSize}) {
    if (faces.isEmpty) {
      return FaceValidationResult.failure('No face detected');
    }
    if (faces.length > 1) {
      return FaceValidationResult.failure('Multiple faces detected');
    }

    final face = faces.single;
    final landmarks = face.landmarks;
    if (landmarks.leftEye == null ||
        landmarks.rightEye == null ||
        landmarks.noseTip == null ||
        landmarks.mouth == null) {
      return FaceValidationResult.failure('Face landmarks not detected');
    }

    final box = face.boundingBox;
    final rect = Rect.fromLTRB(box.left, box.top, box.right, box.bottom);
    final resolvedImageSize = imageSize ?? face.originalSize;

    // For static images/avatars, we relax the size constraint significantly.
    // We only require a face that is at least 30x30 pixels.
    const double minFaceSize = 30.0;
    if (rect.width < minFaceSize || rect.height < minFaceSize) {
      return FaceValidationResult.failure(
        'Face too small',
        boundingBox: rect,
        imageSize: resolvedImageSize,
      );
    }

    // No maximum face size restriction for static avatars, and no quality check restriction.
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
  }) {
    if (faces.isEmpty) {
      return MultiFaceValidationResult(
        faces: const [],
        imageSize: imageSize,
        message: 'Looking for a face',
      );
    }

    final validFaces = <DetectedFace>[];
    var rejectedMessage = 'Face not clear';
    for (final face in faces) {
      final validation = _validateSingleFace(face, imageSize);
      if (validation.valid && validation.boundingBox != null) {
        validFaces.add(
          DetectedFace(
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
      );
    }
    return MultiFaceValidationResult(
      faces: validFaces,
      imageSize: imageSize,
      message: validFaces.length == 1
          ? 'Hold still'
          : '${validFaces.length} faces detected',
    );
  }

  FaceValidationResult _validateSingleFace(mp.Face face, Size imageSize) {
    final landmarks = face.landmarks;
    if (landmarks.leftEye == null ||
        landmarks.rightEye == null ||
        landmarks.noseTip == null ||
        landmarks.mouth == null) {
      return FaceValidationResult.failure('Face landmarks not detected');
    }

    final box = face.boundingBox;
    final rect = Rect.fromLTRB(box.left, box.top, box.right, box.bottom);
    final shortSide = min(imageSize.width, imageSize.height);
    final minFaceSize = shortSide * 0.20;
    if (rect.width < minFaceSize || rect.height < minFaceSize) {
      return FaceValidationResult.failure(
        'Move closer to the camera',
        boundingBox: rect,
        imageSize: imageSize,
      );
    }
    final maxFaceSize = shortSide * 0.82;
    if (rect.width > maxFaceSize || rect.height > maxFaceSize) {
      return FaceValidationResult.failure(
        'Move slightly back',
        boundingBox: rect,
        imageSize: imageSize,
      );
    }

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
  });

  final List<DetectedFace> faces;
  final Size imageSize;
  final String message;
}

class DetectedFace {
  const DetectedFace({
    required this.boundingBox,
    required this.qualityScore,
    required this.yawEstimate,
  });

  final Rect boundingBox;
  final double qualityScore;
  final double yawEstimate;
}
