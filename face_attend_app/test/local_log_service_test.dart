import 'package:flutter_test/flutter_test.dart';
import 'package:face_attend_app/src/services/local_log_service.dart';

void main() {
  group('LocalLogService - Log Retention Date Calculation', () {
    test('Calculates correct 5-working-day cutoff when today is a Monday', () {
      // 2026-06-29 is a Monday
      final now = DateTime(2026, 6, 29, 15, 30);
      final expectedCutoff = DateTime(2026, 6, 23); // Tuesday

      final cutoff = LocalLogService.instance.getCutoffDateForTesting(now);
      expect(cutoff, expectedCutoff);
    });

    test('Calculates correct 5-working-day cutoff when today is a Wednesday', () {
      // 2026-07-01 is a Wednesday
      final now = DateTime(2026, 7, 1, 10, 0);
      final expectedCutoff = DateTime(2026, 6, 25); // Thursday

      final cutoff = LocalLogService.instance.getCutoffDateForTesting(now);
      expect(cutoff, expectedCutoff);
    });

    test('Calculates correct 5-working-day cutoff when today is a Saturday (weekend)', () {
      // 2026-06-27 is a Saturday
      final now = DateTime(2026, 6, 27, 23, 59);
      final expectedCutoff = DateTime(2026, 6, 22); // Monday

      final cutoff = LocalLogService.instance.getCutoffDateForTesting(now);
      expect(cutoff, expectedCutoff);
    });

    test('Calculates correct 5-working-day cutoff when today is a Sunday (weekend)', () {
      // 2026-06-28 is a Sunday
      final now = DateTime(2026, 6, 28, 0, 1);
      final expectedCutoff = DateTime(2026, 6, 22); // Monday

      final cutoff = LocalLogService.instance.getCutoffDateForTesting(now);
      expect(cutoff, expectedCutoff);
    });
  });
}
