import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/session.dart';

class SecureSessionStore {
  static const _key = 'face_attend_session';
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  Future<MobileSession?> read() async {
    final raw = await _storage.read(key: _key);
    if (raw == null) return null;
    final sessionMap = jsonDecode(raw) as Map<String, dynamic>;
    return MobileSession.fromJson(sessionMap);
  }

  Future<void> write(MobileSession session) async {
    await _storage.write(key: _key, value: jsonEncode(session.toJson()));
  }

  Future<void> clear() async {
    await _storage.delete(key: _key);
  }
}
