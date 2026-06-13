import 'dart:typed_data';
import 'dart:math' as math;

import 'package:face_detection_tflite/face_detection_tflite.dart' as mp;
import 'package:flutter/services.dart';

class ArcFaceEmbeddingService {
  static const _channel = MethodChannel('face_attend_app/arcface');

  Future<Float32List> embed({
    required Uint8List imageBytes,
    required mp.Face face,
  }) async {
    final landmarks = _landmarks(face);
    final result = await _channel.invokeMethod<List<dynamic>>('embed', {
      'imageBytes': imageBytes,
      'landmarks': landmarks,
    });
    if (result == null || result.isEmpty) {
      throw StateError('ArcFace returned an empty embedding.');
    }
    return Float32List.fromList(
      result.map((value) => (value as num).toDouble()).toList(),
    );
  }

  Map<String, dynamic> _landmarks(mp.Face face) {
    final landmarks = face.landmarks;
    final leftEye = landmarks.leftEye;
    final rightEye = landmarks.rightEye;
    final nose = landmarks.noseTip;
    final mouth = landmarks.mouth;
    final mesh = face.mesh;
    if (leftEye == null || rightEye == null || nose == null || mouth == null) {
      throw StateError('Face landmarks not detected.');
    }
    var mouthLeft = mesh != null && mesh.length > 291 ? mesh[61] : null;
    var mouthRight = mesh != null && mesh.length > 291 ? mesh[291] : null;
    if (mouthLeft == null || mouthRight == null) {
      final eyeDx = rightEye.x - leftEye.x;
      final eyeDy = rightEye.y - leftEye.y;
      final eyeDistance = math.sqrt(eyeDx * eyeDx + eyeDy * eyeDy);
      if (eyeDistance <= 1) {
        throw StateError('Face landmarks are too close.');
      }
      final ux = eyeDx / eyeDistance;
      final uy = eyeDy / eyeDistance;
      final halfMouthWidth = eyeDistance * 0.42;
      mouthLeft = mp.Point(
        mouth.x - ux * halfMouthWidth,
        mouth.y - uy * halfMouthWidth,
        mouth.z,
      );
      mouthRight = mp.Point(
        mouth.x + ux * halfMouthWidth,
        mouth.y + uy * halfMouthWidth,
        mouth.z,
      );
    }
    return {
      'leftEye': _point(leftEye),
      'rightEye': _point(rightEye),
      'nose': _point(nose),
      'mouthLeft': _point(mouthLeft),
      'mouthRight': _point(mouthRight),
    };
  }

  Map<String, double> _point(mp.Point point) => {'x': point.x, 'y': point.y};
}
