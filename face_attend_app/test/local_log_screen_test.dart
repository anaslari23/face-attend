import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:face_attend_app/src/models/session.dart';
import 'package:face_attend_app/src/screens/local_log_screen.dart';
import 'package:face_attend_app/src/services/local_log_service.dart';

void main() {
  const testSession = MobileSession(
    baseUrl: 'https://test.odoo.com',
    db: 'test_db',
    token: 'test_token',
    deviceId: 'device_abc',
    deviceName: 'Test Scanner',
  );

  setUp(() {
    // Inject mock logs to avoid trying to read/write real files
    final now = DateTime.now();
    final mockLogs = [
      LocalPunchLog(
        id: 'log_synced_success',
        timestamp: now,
        employeeName: 'John Doe',
        isSynced: true,
        payload: {
          'accepted': true,
          'match_score': 0.85,
          'threshold': 0.70,
          'liveness_passed': true,
          'liveness_score': 0.90,
          'device_id': 'device_abc',
        },
      ),
      LocalPunchLog(
        id: 'log_offline_pending',
        timestamp: now.subtract(const Duration(hours: 2)),
        employeeName: 'Jane Smith',
        isSynced: false,
        payload: {
          'accepted': true,
          'match_score': 0.88,
          'threshold': 0.70,
          'liveness_passed': true,
          'liveness_score': 0.95,
          'device_id': 'device_abc',
        },
      ),
      LocalPunchLog(
        id: 'log_sync_error',
        timestamp: now.subtract(const Duration(days: 1)),
        employeeName: 'Alice Johnson',
        isSynced: false,
        syncError: '422 Unprocessable Entity: Employee not found',
        payload: {
          'accepted': true,
          'failure_reason': 'unknown_employee',
          'device_id': 'device_abc',
        },
      ),
    ];
    LocalLogService.instance.setCacheForTesting(mockLogs);
  });

  tearDown(() {
    LocalLogService.instance.setCacheForTesting(null);
  });

  testWidgets('LocalLogScreen renders List, Calendar, and Kanban views successfully', (WidgetTester tester) async {
    // Set standard mobile screen size to avoid overflows in widget test
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    // Build the LocalLogScreen
    await tester.pumpWidget(
      const MaterialApp(
        home: LocalLogScreen(session: testSession),
      ),
    );

    // Initial load takes a brief moment to toggle _loading to false
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // 1. LIST VIEW (Default)
    expect(find.text('Scanner Activity Logs'), findsOneWidget);
    expect(find.text('List'), findsOneWidget);
    expect(find.text('Calendar'), findsOneWidget);
    expect(find.text('Kanban'), findsOneWidget);

    // Should find the logs in the list
    expect(find.text('John Doe'), findsOneWidget);
    expect(find.text('Jane Smith'), findsOneWidget);
    expect(find.text('Alice Johnson'), findsOneWidget);

    // 2. CALENDAR VIEW
    // Tap on the Calendar view tab
    await tester.tap(find.text('Calendar'));
    await tester.pumpAndSettle();

    // Verify calendar elements are displayed
    expect(find.text('Mo'), findsOneWidget);
    expect(find.text('Tu'), findsOneWidget);
    expect(find.text('We'), findsOneWidget);
    expect(find.text('Th'), findsOneWidget);
    expect(find.text('Fr'), findsOneWidget);
    expect(find.text('Sa'), findsOneWidget);
    expect(find.text('Su'), findsOneWidget);

    // 3. KANBAN VIEW
    // Tap on the Kanban view tab
    await tester.tap(find.text('Kanban'));
    await tester.pumpAndSettle();

    // Verify Kanban columns are displayed
    expect(find.text('Offline Queue'), findsAtLeastNWidgets(1));
    expect(find.text('Sync Error'), findsAtLeastNWidgets(1));
    expect(find.text('Synced Logs'), findsAtLeastNWidgets(1));

    // Verify items are displayed in Kanban mode
    expect(find.text('John Doe'), findsOneWidget);
    expect(find.text('Jane Smith'), findsOneWidget);
    expect(find.text('Alice Johnson'), findsOneWidget);
  });
}
