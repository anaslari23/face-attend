class LocalLogServiceDateCalc {
  DateTime _getCutoffDate(DateTime now) {
    int workingDaysFound = 0;
    DateTime current = DateTime(now.year, now.month, now.day);
    while (true) {
      if (current.weekday != 6 && current.weekday != 7) { // 6 = Saturday, 7 = Sunday
        workingDaysFound++;
        if (workingDaysFound == 5) {
          return current;
        }
      }
      current = current.subtract(Duration(days: 1));
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

  // Test Saturday
  {
    final now = DateTime(2026, 6, 27, 23, 59);
    final expected = DateTime(2026, 6, 22);
    final actual = service._getCutoffDate(now);
    assert(actual == expected, "Saturday test failed: expected $expected, got $actual");
  }

  // Test Sunday
  {
    final now = DateTime(2026, 6, 28, 0, 1);
    final expected = DateTime(2026, 6, 22);
    final actual = service._getCutoffDate(now);
    assert(actual == expected, "Sunday test failed: expected $expected, got $actual");
  }

  print("All date pruning tests passed successfully!");
}
