import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';

class DeviceService {
  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

  Future<DeviceIdentity> identity() async {
    if (Platform.isAndroid) {
      final info = await _deviceInfo.androidInfo;
      return DeviceIdentity(id: info.id, name: '${info.manufacturer} ${info.model}');
    }
    if (Platform.isIOS) {
      final info = await _deviceInfo.iosInfo;
      return DeviceIdentity(
        id: info.identifierForVendor ?? info.name,
        name: '${info.name} ${info.model}',
      );
    }
    final info = await _deviceInfo.deviceInfo;
    return DeviceIdentity(id: info.data.toString(), name: Platform.operatingSystem);
  }

  Future<String> appVersion() async {
    final info = await PackageInfo.fromPlatform();
    return '${info.version}+${info.buildNumber}';
  }
}

class DeviceIdentity {
  const DeviceIdentity({required this.id, required this.name});

  final String id;
  final String name;
}
