import 'package:flutter_test/flutter_test.dart';
import 'package:face_attend_app/src/services/local_log_service.dart';

void main() {
  group('LocalLogService - Log Retention Date Calculation', () {
    test(
      'Calculates correct cutoff when today is a Monday (before 11:50 PM)',
      () {
        // 2026-06-29 is a Monday
        final now = DateTime(2026, 6, 29, 15, 30);
        final expectedCutoff = DateTime(2026, 6, 23); // Tuesday (6 days ago)

        final cutoff = LocalLogService.instance.getCutoffDateForTesting(now);
        expect(cutoff, expectedCutoff);
      },
    );

    test(
      'Calculates correct cutoff when today is a Wednesday (before 11:50 PM)',
      () {
        // 2026-07-01 is a Wednesday
        final now = DateTime(2026, 7, 1, 10, 0);
        final expectedCutoff = DateTime(2026, 6, 25); // Thursday (6 days ago)

        final cutoff = LocalLogService.instance.getCutoffDateForTesting(now);
        expect(cutoff, expectedCutoff);
      },
    );

    test(
      'Calculates correct cutoff when today is a Saturday (after 11:50 PM)',
      () {
        // 2026-06-27 is a Saturday
        final now = DateTime(2026, 6, 27, 23, 59);
        final expectedCutoff = DateTime(2026, 6, 22); // Monday (5 days ago)

        final cutoff = LocalLogService.instance.getCutoffDateForTesting(now);
        expect(cutoff, expectedCutoff);
      },
    );

    test(
      'Calculates correct cutoff when today is a Sunday (before 11:50 PM)',
      () {
        // 2026-06-28 is a Sunday
        final now = DateTime(2026, 6, 28, 0, 1);
        final expectedCutoff = DateTime(2026, 6, 22); // Monday (6 days ago)

        final cutoff = LocalLogService.instance.getCutoffDateForTesting(now);
        expect(cutoff, expectedCutoff);
      },
    );

    test('Boundary check: June 30th before 11:50 PM retains June 24th', () {
      final now = DateTime(2026, 6, 30, 23, 49);
      final expectedCutoff = DateTime(2026, 6, 24);

      final cutoff = LocalLogService.instance.getCutoffDateForTesting(now);
      expect(cutoff, expectedCutoff);
    });

    test('Boundary check: June 30th at 11:50 PM prunes June 24th', () {
      final now = DateTime(2026, 6, 30, 23, 50);
      final expectedCutoff = DateTime(2026, 6, 25);

      final cutoff = LocalLogService.instance.getCutoffDateForTesting(now);
      expect(cutoff, expectedCutoff);
    });

    test('Formats backend punch timestamps as UTC', () {
      final localTimestamp = DateTime.parse('2026-07-15T09:59:27+05:30');

      final formatted = LocalLogService.instance.formatBackendTimestamp(
        localTimestamp,
      );

      expect(formatted, '2026-07-15 04:29:27');
    });
  });
}
