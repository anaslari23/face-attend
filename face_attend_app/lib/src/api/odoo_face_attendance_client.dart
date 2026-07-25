import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/session.dart';

class OdooFaceAttendanceClient {
  OdooFaceAttendanceClient({
    required this.baseUrl,
    this.db,
    this.token,
    this.deviceId,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  final String baseUrl;
  final String? db;
  final String? token;
  final String? deviceId;
  final http.Client _http;

  Future<List<String>> listDatabases() async {
    final payload = await getPublicConfig();
    if (payload.containsKey('error')) {
      throw FaceAttendanceApiException(
        statusCode: 400,
        message:
            payload['error']['data']?['message']?.toString() ??
            'Failed to fetch databases',
      );
    }
    final dbs = <String>[];
    
    // Check for 'db_name'
    final dbNameVal = payload['db_name'];
    if (dbNameVal is List) {
      dbs.addAll(dbNameVal.map((e) => e.toString()));
    } else if (dbNameVal is String && dbNameVal.isNotEmpty) {
      dbs.add(dbNameVal);
    }
    
    // Check for 'databases'
    final databasesVal = payload['databases'];
    if (databasesVal is List) {
      dbs.addAll(databasesVal.map((e) => e.toString()));
    }
    
    // Check for 'db'
    final dbVal = payload['db'];
    if (dbVal is List) {
      dbs.addAll(dbVal.map((e) => e.toString()));
    } else if (dbVal is String && dbVal.isNotEmpty) {
      dbs.add(dbVal);
    }

    return dbs.toSet().toList();
  }


  Future<Map<String, dynamic>> getPublicConfig() async {
    return _get('/public/config', authenticated: false);
  }

  Future<MobileSession> setupScanner({
    required String db,
    required String setupCode,
    required String deviceId,
  }) async {
    final requestBody = {
      'setup_code': setupCode,
      'device_try_to_connect': deviceId,
    };
    print(
      '[OdooFaceAttendanceClient] setupScanner Request: ${jsonEncode(requestBody)}',
    );

    final payload = await _post(
      '/face_attendance/scanner/setup',
      requestBody,
      authenticated: false,
      extraDb: db,
    );

    print(
      '[OdooFaceAttendanceClient] setupScanner Response: ${jsonEncode(payload)}',
    );

    if (payload.containsKey('error') && payload['error'] != null) {
      final errorVal = payload['error'];
      String msg = 'Failed to setup scanner';
      if (errorVal is Map) {
        msg =
            errorVal['data']?['message']?.toString() ??
            errorVal['message']?.toString() ??
            msg;
      } else {
        msg = errorVal.toString();
      }
      throw FaceAttendanceApiException(statusCode: 400, message: msg);
    }

    if (!payload.containsKey('token') || payload['token'] == null) {
      throw const FaceAttendanceApiException(
        statusCode: 400,
        message: 'Invalid response from server: Missing authorization token',
      );
    }

    if (!payload.containsKey('device') || payload['device'] == null) {
      throw const FaceAttendanceApiException(
        statusCode: 400,
        message: 'Invalid response from server: Missing device information',
      );
    }

    final device = payload['device'] as Map<String, dynamic>;
    final generatedDeviceId = payload['generated_device_id'] as String?;
    return MobileSession(
      baseUrl: baseUrl,
      db: db,
      token: payload['token'] as String,
      deviceId: device['device_uid'] as String? ?? deviceId,
      deviceName: device['name'] as String? ?? 'Shared Scanner',
      generatedDeviceId: generatedDeviceId,
    );
  }

  Future<ScannerEmployeeSync> scannerEmployees({
    Map<int, String> knownAvatarWriteDates = const {},
    String? modelVersion,
  }) async {
    Map<String, dynamic> payload;
    try {
      payload = await _post('/face_attendance/scanner/employees', {
        'model_version': modelVersion,
        'known_avatar_write_dates': knownAvatarWriteDates.map(
          (key, value) => MapEntry(key.toString(), value),
        ),
      });
    } on FaceAttendanceApiException catch (error) {
      if (error.statusCode != 405) rethrow;
      payload = await _get('/face_attendance/scanner/employees');
    }
    return ScannerEmployeeSync.fromJson(payload);
  }

  Future<AttendanceStatus> status() async {
    final payload = await _get('/face_attendance/status');
    return AttendanceStatus.fromJson(
      payload['attendance'] as Map<String, dynamic>,
    );
  }

  Future<PunchResult> punch({
    required bool accepted,
    int? matchedEmployeeId,
    required double matchScore,
    required double threshold,
    required String deviceId,
    required String appVersion,
    String? failureReason,
    double? secondBestConfidence,
    String? embeddingSource,
    int? reviewEmbeddingId,
    bool needsReview = false,
    bool livenessPassed = false,
    double? livenessScore,
    double? spoofScore,
    String? timestamp,
    Map<String, dynamic>? fullLogData,
  }) async {
    final body = <String, dynamic>{
      'accepted': accepted,
      'matched_employee_id': matchedEmployeeId,
      'match_score': matchScore,
      'threshold': threshold,
      'device_id': deviceId,
      'app_version': appVersion,
      'failure_reason': failureReason,
      'second_best_confidence': secondBestConfidence,
      'embedding_source': embeddingSource,
      'review_embedding_id': reviewEmbeddingId,
      'needs_review': needsReview,
      'liveness_passed': livenessPassed,
      'liveness_score': livenessScore,
      'spoof_score': spoofScore,
      'full_log_data': ?fullLogData,
    };
    if (timestamp != null) {
      body['timestamp'] = timestamp;
    }
    if (fullLogData != null) {
      _printLongMessage('FULL LOG DATA', jsonEncode(fullLogData));
    }
    final payload = await _post('/face_attendance/punch', body);
    return PunchResult.fromJson(payload);
  }

  Future<Map<String, dynamic>> _get(
    String path, {
    bool authenticated = true,
  }) async {
    final requestUrl = _uri(path);
    print('API CALL: GET URL: $requestUrl');
    final response = await _http.get(
      requestUrl,
      headers: _headers(authenticated: authenticated, path: path),
    );
    print('DEBUG CLIENT RESPONSE STATUS: ${response.statusCode}');
    _printLongMessage('DEBUG CLIENT RESPONSE BODY', response.body);
    return _decode(response);
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body, {
    bool authenticated = true,
    String? extraDb,
  }) async {
    final resolvedHeaders = _headers(
      authenticated: authenticated,
      extraDb: extraDb,
      path: path,
    );
    final requestUrl = _uri(path);
    print('API CALL: POST URL: $requestUrl');
    print('DEBUG CLIENT HEADERS: $resolvedHeaders');
    _printLongMessage('DEBUG CLIENT BODY', jsonEncode(body));
    final response = await _http.post(
      requestUrl,
      headers: resolvedHeaders,
      body: jsonEncode(body),
    );
    print('DEBUG CLIENT RESPONSE STATUS: ${response.statusCode}');
    _printLongMessage('DEBUG CLIENT RESPONSE BODY', response.body);
    return _decode(response);
  }

  void _printLongMessage(String label, String message) {
    const chunkSize = 800;
    final totalChunks = (message.length / chunkSize).ceil();

    if (totalChunks == 0) {
      print('$label:');
      return;
    }

    for (var index = 0; index < totalChunks; index++) {
      final start = index * chunkSize;
      final end = (start + chunkSize < message.length)
          ? start + chunkSize
          : message.length;
      print(
        '$label [${index + 1}/$totalChunks]: ${message.substring(start, end)}',
      );
    }
  }

  Uri _uri(String path) {
    final normalizedBase = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return Uri.parse('$normalizedBase$path');
  }

  Map<String, String> _headers({
    bool authenticated = true,
    String? extraDb,
    String? path,
  }) {
    final currentDb = extraDb ?? db;
    // Odoo 17 classifies requests with 'Content-Type: application/json' strictly as JSON-RPC (JsonRequest).
    // For custom face_attendance HTTP routes, we use 'text/plain' to avoid Odoo raising a 422 Unprocessable Entity error.
    final contentType = (path != null && path.contains('face_attendance'))
        ? 'text/plain'
        : 'application/json';
    return {
      'Content-Type': contentType,
      if (authenticated && token != null) 'Authorization': 'Bearer $token',
      if (deviceId != null && deviceId!.isNotEmpty) 'X-Device-ID': deviceId!,
      ...?(currentDb == null ? null : {'X-Odoo-Database': currentDb}),
    };
  }

  Map<String, dynamic> _decode(http.Response response) {
    if (response.statusCode >= 400) {
      String errorMessage = 'Request failed with status ${response.statusCode}';
      try {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        errorMessage = decoded['error']?.toString() ?? errorMessage;
      } catch (_) {
        // Not JSON, probably HTML error page
        if (response.body.isNotEmpty) {
          final pMatch = RegExp(
            r'<p>(.*?)</p>',
            dotAll: true,
            caseSensitive: false,
          ).firstMatch(response.body);
          if (pMatch != null) {
            errorMessage = pMatch.group(1)!.trim();
          } else {
            // Fallback: strip HTML tags
            final cleanBody = response.body
                .replaceAll(RegExp(r'<[^>]*>'), '')
                .trim();
            errorMessage = cleanBody.isNotEmpty
                ? (cleanBody.length > 150
                      ? '${cleanBody.substring(0, 150)}...'
                      : cleanBody)
                : errorMessage;
          }
        }
      }
      throw FaceAttendanceApiException(
        statusCode: response.statusCode,
        message: errorMessage,
      );
    }

    if (response.body.isEmpty) return <String, dynamic>{};

    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        if (decoded.containsKey('error') && decoded['error'] != null) {
          final errorVal = decoded['error'];
          String msg = 'Request failed';
          if (errorVal is Map) {
            msg =
                errorVal['data']?['message']?.toString() ??
                errorVal['message']?.toString() ??
                msg;
          } else {
            msg = errorVal.toString();
          }
          throw FaceAttendanceApiException(
            statusCode: response.statusCode,
            message: msg,
          );
        }
        return decoded;
      }
      return <String, dynamic>{};
    } catch (e) {
      if (e is FaceAttendanceApiException) rethrow;
      throw FaceAttendanceApiException(
        statusCode: response.statusCode,
        message: 'Invalid JSON response from server',
      );
    }
  }
}

class FaceAttendanceApiException implements Exception {
  const FaceAttendanceApiException({
    required this.statusCode,
    required this.message,
  });

  final int statusCode;
  final String message;

  @override
  String toString() => message;
}
