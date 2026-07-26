import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/session.dart';
import 'database_helper.dart';

class SecureSessionStore {
  static const _key = 'face_attend_session';
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  Future<MobileSession?> read() async {
    // 1. Try SQLite Database first
    try {
      final dbSessionMap = await DatabaseHelper.instance.getSession();
      if (dbSessionMap != null && (dbSessionMap['token'] as String? ?? '').isNotEmpty) {
        return MobileSession.fromJson(dbSessionMap);
      }
    } catch (_) {}

    // 2. Fallback to FlutterSecureStorage
    final raw = await _storage.read(key: _key);
    if (raw == null) return null;
    final sessionMap = jsonDecode(raw) as Map<String, dynamic>;
    
    // Save into SQLite if restored from secure storage
    try {
      await DatabaseHelper.instance.saveSession(sessionMap);
    } catch (_) {}

    return MobileSession.fromJson(sessionMap);
  }

  Future<void> write(MobileSession session) async {
    final sessionJson = session.toJson();
    await DatabaseHelper.instance.saveSession(sessionJson);
    await _storage.write(key: _key, value: jsonEncode(sessionJson));
  }

  Future<void> clear() async {
    await DatabaseHelper.instance.clearSession();
    await _storage.delete(key: _key);
  }
}
