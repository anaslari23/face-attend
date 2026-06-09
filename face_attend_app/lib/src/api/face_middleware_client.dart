import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class FaceMiddlewareClient {
  FaceMiddlewareClient({
    required this.baseUrl,
    required this.apiKey,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  final String baseUrl;
  final String apiKey;
  final http.Client _http;

  Future<RegisterFaceResult> register({
    required int employeeId,
    required String employeeName,
    required List<String> imagePaths,
  }) async {
    final request = http.MultipartRequest('POST', _uri('/register'));
    request.headers['X-API-Key'] = apiKey;
    request.fields['employee_id'] = employeeId.toString();
    request.fields['employee_name'] = employeeName;
    for (final path in imagePaths) {
      request.files.add(await http.MultipartFile.fromPath('files', path));
    }
    final payload = await _send(request);
    return RegisterFaceResult.fromJson(payload);
  }

  Future<FaceMatchResult> match({required String imagePath}) async {
    final request = http.MultipartRequest('POST', _uri('/match'));
    request.headers['X-API-Key'] = apiKey;
    request.files.add(await http.MultipartFile.fromPath('file', imagePath));
    final payload = await _send(request);
    return FaceMatchResult.fromJson(payload);
  }

  Future<MultiFaceMatchResult> matchFaces({required String imagePath}) async {
    final request = http.MultipartRequest('POST', _uri('/match/faces'));
    request.headers['X-API-Key'] = apiKey;
    request.files.add(await http.MultipartFile.fromPath('file', imagePath));
    final payload = await _send(request);
    return MultiFaceMatchResult.fromJson(payload);
  }

  Uri _uri(String path) {
    final normalizedBase = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return Uri.parse('$normalizedBase$path');
  }

  Future<Map<String, dynamic>> _send(http.MultipartRequest request) async {
    final http.StreamedResponse streamed;
    try {
      streamed = await _http.send(request);
    } on SocketException catch (error) {
      throw FaceMiddlewareException(
        statusCode: 0,
        message: _connectionMessage(request.url, error),
      );
    } on http.ClientException catch (error) {
      throw FaceMiddlewareException(
        statusCode: 0,
        message: _connectionMessage(request.url, error),
      );
    }

    final response = await http.Response.fromStream(streamed);
    final body = response.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = body['detail'];
      String message = 'Middleware request failed';
      if (detail is Map<String, dynamic>) {
        message =
            detail['message']?.toString() ??
            detail['code']?.toString() ??
            message;
      }
      throw FaceMiddlewareException(
        statusCode: response.statusCode,
        message: message,
      );
    }
    return body;
  }

  String _connectionMessage(Uri uri, Object error) {
    final host = uri.host.toLowerCase();
    if (host == '127.0.0.1' || host == 'localhost' || host == '::1') {
      return 'Middleware is set to $host, which points to this phone. Use your Mac IP address, for example http://192.168.x.x:8019.';
    }
    return 'Cannot reach middleware at ${uri.origin}. Check that the middleware is running and the phone is on the same network. $error';
  }
}

class RegisterFaceResult {
  const RegisterFaceResult({
    required this.employeeId,
    required this.framesAccepted,
    required this.embeddingDimension,
  });

  final int employeeId;
  final int framesAccepted;
  final int embeddingDimension;

  factory RegisterFaceResult.fromJson(Map<String, dynamic> json) {
    return RegisterFaceResult(
      employeeId: json['employee_id'] as int,
      framesAccepted: json['frames_accepted'] as int,
      embeddingDimension: json['embedding_dimension'] as int,
    );
  }
}

class FaceMatchResult {
  const FaceMatchResult({
    required this.matched,
    required this.confidence,
    required this.threshold,
    this.employeeId,
    this.employeeName,
    this.reason,
    this.secondBestConfidence,
    this.boundingBox,
  });

  final bool matched;
  final double confidence;
  final double threshold;
  final int? employeeId;
  final String? employeeName;
  final String? reason;
  final double? secondBestConfidence;
  final MiddlewareFaceBox? boundingBox;

  factory FaceMatchResult.fromJson(Map<String, dynamic> json) {
    final employee = json['employee'];
    return FaceMatchResult(
      matched: json['matched'] == true,
      confidence: (json['confidence'] as num).toDouble(),
      threshold: (json['threshold'] as num).toDouble(),
      employeeId: employee is Map<String, dynamic>
          ? employee['employee_id'] as int?
          : null,
      employeeName: employee is Map<String, dynamic>
          ? employee['employee_name'] as String?
          : null,
      reason: json['reason'] as String?,
      secondBestConfidence: (json['second_best_confidence'] as num?)
          ?.toDouble(),
      boundingBox: json['bbox'] is Map<String, dynamic>
          ? MiddlewareFaceBox.fromJson(json['bbox'] as Map<String, dynamic>)
          : null,
    );
  }
}

class MiddlewareFaceBox {
  const MiddlewareFaceBox({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final double left;
  final double top;
  final double right;
  final double bottom;

  factory MiddlewareFaceBox.fromJson(Map<String, dynamic> json) {
    return MiddlewareFaceBox(
      left: (json['left'] as num).toDouble(),
      top: (json['top'] as num).toDouble(),
      right: (json['right'] as num).toDouble(),
      bottom: (json['bottom'] as num).toDouble(),
    );
  }
}

class MultiFaceMatchResult {
  const MultiFaceMatchResult({
    required this.imageWidth,
    required this.imageHeight,
    required this.faces,
  });

  final int imageWidth;
  final int imageHeight;
  final List<FaceMatchResult> faces;

  factory MultiFaceMatchResult.fromJson(Map<String, dynamic> json) {
    return MultiFaceMatchResult(
      imageWidth: json['image_width'] as int,
      imageHeight: json['image_height'] as int,
      faces: (json['faces'] as List<dynamic>? ?? [])
          .map((face) => FaceMatchResult.fromJson(face as Map<String, dynamic>))
          .toList(),
    );
  }
}

class FaceMiddlewareException implements Exception {
  const FaceMiddlewareException({
    required this.statusCode,
    required this.message,
  });

  final int statusCode;
  final String message;

  @override
  String toString() => message;
}

Future<void> deleteImageQuietly(String path) async {
  try {
    await File(path).delete();
  } catch (_) {
    // Temporary camera image cleanup best effort.
  }
}
