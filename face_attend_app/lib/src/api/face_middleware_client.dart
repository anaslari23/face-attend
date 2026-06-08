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

  Uri _uri(String path) {
    final normalizedBase = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    return Uri.parse('$normalizedBase$path');
  }

  Future<Map<String, dynamic>> _send(http.MultipartRequest request) async {
    final streamed = await _http.send(request);
    final response = await http.Response.fromStream(streamed);
    final body = response.body.isEmpty ? <String, dynamic>{} : jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = body['detail'];
      String message = 'Middleware request failed';
      if (detail is Map<String, dynamic>) {
        message = detail['message']?.toString() ?? detail['code']?.toString() ?? message;
      }
      throw FaceMiddlewareException(statusCode: response.statusCode, message: message);
    }
    return body;
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
  });

  final bool matched;
  final double confidence;
  final double threshold;
  final int? employeeId;
  final String? employeeName;
  final String? reason;

  factory FaceMatchResult.fromJson(Map<String, dynamic> json) {
    final employee = json['employee'];
    return FaceMatchResult(
      matched: json['matched'] == true,
      confidence: (json['confidence'] as num).toDouble(),
      threshold: (json['threshold'] as num).toDouble(),
      employeeId: employee is Map<String, dynamic> ? employee['employee_id'] as int? : null,
      employeeName: employee is Map<String, dynamic> ? employee['employee_name'] as String? : null,
      reason: json['reason'] as String?,
    );
  }
}

class FaceMiddlewareException implements Exception {
  const FaceMiddlewareException({required this.statusCode, required this.message});

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
