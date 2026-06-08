import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/session.dart';

class SecureSessionStore {
  static const _key = 'face_attend_session';
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  Future<MobileSession?> read() async {
    final raw = await _storage.read(key: _key);
    if (raw == null) return null;
    return MobileSession.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> write(MobileSession session) {
    return _storage.write(key: _key, value: jsonEncode(session.toJson()));
  }

  Future<void> clear() {
    return _storage.delete(key: _key);
  }
}
