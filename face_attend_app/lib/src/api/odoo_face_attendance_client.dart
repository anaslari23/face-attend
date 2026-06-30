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
    final payload = await _post('/web/database/list', {
      'jsonrpc': '2.0',
      'method': 'call',
      'params': <String, dynamic>{},
    }, authenticated: false);
    if (payload.containsKey('error')) {
      throw FaceAttendanceApiException(
        statusCode: 400,
        message:
            payload['error']['data']?['message']?.toString() ??
            'Failed to fetch databases',
      );
    }
    if (payload.containsKey('result')) {
      final list = payload['result'] as List;
      return list.map((e) => e.toString()).toList();
    }
    return [];
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
    print('[OdooFaceAttendanceClient] setupScanner Request: ${jsonEncode(requestBody)}');

    final payload = await _post(
      '/face_attendance/scanner/setup',
      requestBody,
      authenticated: false,
      extraDb: db,
    );

    print('[OdooFaceAttendanceClient] setupScanner Response: ${jsonEncode(payload)}');

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
    };
    if (timestamp != null) {
      body['timestamp'] = timestamp;
    }
    final payload = await _post('/face_attendance/punch', body);
    return PunchResult.fromJson(payload);
  }

  Future<Map<String, dynamic>> _get(String path, {bool authenticated = true}) async {
    final response = await _http.get(_uri(path), headers: _headers(authenticated: authenticated));
    return _decode(response);
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body, {
    bool authenticated = true,
    String? extraDb,
  }) async {
    final response = await _http.post(
      _uri(path),
      headers: _headers(authenticated: authenticated, extraDb: extraDb),
      body: jsonEncode(body),
    );
    return _decode(response);
  }

  Uri _uri(String path) {
    final normalizedBase = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return Uri.parse('$normalizedBase$path');
  }

  Map<String, String> _headers({bool authenticated = true, String? extraDb}) {
    final currentDb = extraDb ?? db;
    return {
      'Content-Type': 'application/json',
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
          errorMessage +=
              ': ${response.body.substring(0, response.body.length > 100 ? 100 : response.body.length)}';
        }
      }
      throw FaceAttendanceApiException(
        statusCode: response.statusCode,
        message: errorMessage,
      );
    }

    if (response.body.isEmpty) return <String, dynamic>{};

    try {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
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
