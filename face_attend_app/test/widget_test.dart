import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter/services.dart';
import 'package:face_attend_app/main.dart';
import 'package:face_attend_app/src/models/session.dart';

void _dummyCallback() {}

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async {
        return '.';
      },
    );
  });

  testWidgets('shows scanner setup when no session is stored', (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    await tester.pumpWidget(const FaceAttendApp());
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('PISmartPunch'), findsOneWidget);
    expect(find.text('Save Scanner'), findsOneWidget);
  });

  testWidgets('shows popup when HomeScreen is mounted with justLoggedIn = true', (tester) async {
    const session = MobileSession(
      baseUrl: 'http://test.url',
      db: 'test_db',
      token: 'test_token',
      deviceId: 'test_device_id',
      deviceName: 'My Scanner Device',
      generatedDeviceId: 'gen_device_123',
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: HomeScreen(
            session: session,
            onLogout: _dummyCallback,
            justLoggedIn: true,
          ),
        ),
      ),
    );

    // Let the addPostFrameCallback trigger and general dialog transition animate
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Scanner Connected!'), findsOneWidget);
    expect(find.text('My Scanner Device'), findsAtLeastNWidgets(1));
    expect(find.text('gen_device_123'), findsAtLeastNWidgets(1));
  });
}
