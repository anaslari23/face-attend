import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/session.dart';

class OdooFaceAttendanceClient {
  OdooFaceAttendanceClient({
    required this.baseUrl,
    this.db,
    this.token,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  final String baseUrl;
  final String? db;
  final String? token;
  final http.Client _http;

  Future<List<String>> listDatabases() async {
    final payload = await _post(
      '/web/database/list',
      {
        'jsonrpc': '2.0',
        'method': 'call',
        'params': <String, dynamic>{},
      },
      authenticated: false,
    );
    if (payload.containsKey('error')) {
      throw FaceAttendanceApiException(
        statusCode: 400,
        message: payload['error']['data']?['message']?.toString() ?? 'Failed to fetch databases',
      );
    }
    if (payload.containsKey('result')) {
      final list = payload['result'] as List;
      return list.map((e) => e.toString()).toList();
    }
    return [];
  }

  Future<MobileSession> login({
    required String db,
    required String login,
    required String password,
    required String deviceId,
    required String deviceName,
  }) async {
    final payload = await _post(
      '/face_attendance/login',
      {
        'db': db,
        'login': login,
        'password': password,
        'device_id': deviceId,
        'device_name': deviceName,
      },
      authenticated: false,
      extraDb: db,
    );
    return MobileSession(
      baseUrl: baseUrl,
      db: db,
      token: payload['token'] as String,
      employee: EmployeeProfile.fromJson(payload['employee'] as Map<String, dynamic>),
    );
  }

  Future<AttendanceStatus> status() async {
    final payload = await _get('/face_attendance/status');
    return AttendanceStatus.fromJson(payload['attendance'] as Map<String, dynamic>);
  }

  Future<FaceTemplate?> template() async {
    final payload = await _get('/face_attendance/template');
    final template = payload['template'];
    if (template == null) return null;
    return FaceTemplate.fromJson(template as Map<String, dynamic>);
  }

  Future<EmployeeProfile> enroll({
    required List<List<double>> embeddings,
    required String modelVersion,
    required String deviceId,
    required double qualityScore,
  }) async {
    final payload = await _post(
      '/face_attendance/enroll',
      {
        'embeddings': embeddings,
        'model_version': modelVersion,
        'device_id': deviceId,
        'quality_score': qualityScore,
      },
    );
    return EmployeeProfile.fromJson(payload['employee'] as Map<String, dynamic>);
  }

  Future<PunchResult> punch({
    required bool accepted,
    required double matchScore,
    required double threshold,
    required String deviceId,
    required String appVersion,
    String? failureReason,
  }) async {
    final payload = await _post(
      '/face_attendance/punch',
      {
        'accepted': accepted,
        'match_score': matchScore,
        'threshold': threshold,
        'device_id': deviceId,
        'app_version': appVersion,
        'failure_reason': failureReason,
      },
    );
    return PunchResult.fromJson(payload);
  }

  Future<Map<String, dynamic>> _get(String path) async {
    final response = await _http.get(_uri(path), headers: _headers());
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
    final normalizedBase = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    return Uri.parse('$normalizedBase$path');
  }

  Map<String, String> _headers({bool authenticated = true, String? extraDb}) {
    final currentDb = extraDb ?? db;
    return {
      'Content-Type': 'application/json',
      if (authenticated && token != null) 'Authorization': 'Bearer $token',
      if (currentDb != null) 'X-Odoo-Database': currentDb,
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
          errorMessage += ': ${response.body.substring(0, response.body.length > 100 ? 100 : response.body.length)}';
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
  const FaceAttendanceApiException({required this.statusCode, required this.message});

  final int statusCode;
  final String message;

  @override
  String toString() => message;
}
