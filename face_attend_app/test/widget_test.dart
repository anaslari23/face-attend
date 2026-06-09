import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:face_attend_app/main.dart';

void main() {
  testWidgets('shows login screen when no session is stored', (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    await tester.pumpWidget(const FaceAttendApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('FaceAttend'), findsOneWidget);
    expect(find.text('Sign In'), findsOneWidget);
  });
}
