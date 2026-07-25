// ignore_for_file: avoid_print

class LocalLogServiceDateCalc {
  DateTime _getCutoffDate(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final deleteTime = DateTime(now.year, now.month, now.day, 23, 50);
    if (now.isBefore(deleteTime)) {
      // Before 11:50 PM, we keep data from 6 days ago (e.g. June 24th if today is June 30th)
      return today.subtract(const Duration(days: 6));
    } else {
      // At or after 11:50 PM, the 6-days-ago data is deleted, so the cutoff is June 25th (5 days ago)
      return today.subtract(const Duration(days: 5));
    }
  }
}

void main() {
  final service = LocalLogServiceDateCalc();
  
  // Test Monday
  {
    final now = DateTime(2026, 6, 29, 15, 30);
    final expected = DateTime(2026, 6, 23);
    final actual = service._getCutoffDate(now);
    assert(actual == expected, "Monday test failed: expected $expected, got $actual");
  }

  // Test Wednesday
  {
    final now = DateTime(2026, 7, 1, 10, 0);
    final expected = DateTime(2026, 6, 25);
    final actual = service._getCutoffDate(now);
    assert(actual == expected, "Wednesday test failed: expected $expected, got $actual");
  }

  // Test Saturday (specifically after 11:50 PM boundary)
  {
    final now = DateTime(2026, 6, 27, 23, 59);
    final expected = DateTime(2026, 6, 22);
    final actual = service._getCutoffDate(now);
    assert(actual == expected, "Saturday test failed: expected $expected, got $actual");
  }

  // Test Sunday (specifically before 11:50 PM boundary)
  {
    final now = DateTime(2026, 6, 28, 0, 1);
    final expected = DateTime(2026, 6, 22);
    final actual = service._getCutoffDate(now);
    assert(actual == expected, "Sunday test failed: expected $expected, got $actual");
  }

  // Test 11:50 PM boundary on June 30th (user's specific example)
  {
    // Before 11:50 PM on June 30th, keeping June 24th data
    final nowBefore = DateTime(2026, 6, 30, 23, 49);
    final expectedBefore = DateTime(2026, 6, 24);
    final actualBefore = service._getCutoffDate(nowBefore);
    assert(actualBefore == expectedBefore, "June 30 23:49 boundary failed: expected $expectedBefore, got $actualBefore");

    // Exactly at 11:50 PM on June 30th, June 24th data should be deleted (so cutoff is June 25th)
    final nowAt = DateTime(2026, 6, 30, 23, 50);
    final expectedAt = DateTime(2026, 6, 25);
    final actualAt = service._getCutoffDate(nowAt);
    assert(actualAt == expectedAt, "June 30 23:50 boundary failed: expected $expectedAt, got $actualAt");
  }

  print("All date pruning tests passed successfully!");
}
