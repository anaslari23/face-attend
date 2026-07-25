import 'dart:io';
import 'dart:math';

import 'package:android_id/android_id.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:package_info_plus/package_info_plus.dart';

class DeviceService {
  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();
  static const _secureStorage = FlutterSecureStorage();
  static const _fallbackKey = 'fallback_device_uuid';

  Future<DeviceIdentity> identity() async {
    String? finalId;
    String finalName = 'Unknown Device';

    try {
      if (Platform.isAndroid) {
        try {
          final info = await _deviceInfo.androidInfo;
          finalName = '${info.manufacturer} ${info.model}';

          String? androidId;
          try {
            const androidIdPlugin = AndroidId();
            androidId = await androidIdPlugin.getId();
          } catch (e) {
            debugPrint('Failed to get Android ID via plugin: $e');
          }

          finalId = androidId ?? (info.id.isNotEmpty ? info.id : null);
        } catch (e) {
          debugPrint('Failed to fetch Android device info: $e');
        }
      } else if (Platform.isIOS) {
        try {
          final info = await _deviceInfo.iosInfo;
          finalName = '${info.name} ${info.model}';
          finalId = info.identifierForVendor ?? (info.name.isNotEmpty ? info.name : null);
        } catch (e) {
          debugPrint('Failed to fetch iOS device info: $e');
        }
      } else {
        try {
          final info = await _deviceInfo.deviceInfo;
          finalName = Platform.operatingSystem;
          finalId = info.data.toString();
        } catch (e) {
          debugPrint('Failed to fetch generic device info: $e');
        }
      }
    } catch (e) {
      debugPrint('Unhandled error in identity detection: $e');
    }

    // Fall back to generating/reading a persistent fallback ID if none was found
    if (finalId == null || finalId.trim().isEmpty) {
      finalId = await _getOrCreateFallbackId();
    }

    return DeviceIdentity(id: finalId, name: finalName);
  }

  Future<String> _getOrCreateFallbackId() async {
    try {
      final existing = await _secureStorage.read(key: _fallbackKey);
      if (existing != null && existing.trim().isNotEmpty) {
        return existing;
      }
    } catch (e) {
      debugPrint('Failed to read fallback ID from secure storage: $e');
    }

    final random = Random();
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final randVal = random.nextInt(1000000);
    final generatedId = 'fallback_device_${timestamp}_$randVal';

    try {
      await _secureStorage.write(key: _fallbackKey, value: generatedId);
    } catch (e) {
      debugPrint('Failed to write fallback ID to secure storage: $e');
    }

    return generatedId;
  }

  Future<String> appVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return '${info.version}+${info.buildNumber}';
    } catch (e) {
      debugPrint('Failed to get app version: $e');
      return '1.0.0+1';
    }
  }
}

class DeviceIdentity {
  const DeviceIdentity({required this.id, required this.name});

  final String id;
  final String name;
}
