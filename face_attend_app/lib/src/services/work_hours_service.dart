import 'package:flutter/material.dart';
import 'local_log_service.dart';

class EmployeeShiftStatus {
  const EmployeeShiftStatus({
    required this.hasCheckedIn,
    this.checkInTime,
    required this.workedDuration,
    required this.isUnder8Hours,
  });

  final bool hasCheckedIn;
  final DateTime? checkInTime;
  final Duration workedDuration;
  final bool isUnder8Hours;

  String get workedHoursFormatted {
    final hours = workedDuration.inHours;
    final mins = workedDuration.inMinutes % 60;
    if (hours > 0) {
      return '${hours}h ${mins}m';
    }
    return '${mins}m';
  }

  String get remainingHoursFormatted {
    const totalMinutes = 8 * 60;
    final diff = totalMinutes - workedDuration.inMinutes;
    if (diff <= 0) return '0m';
    final hours = diff ~/ 60;
    final mins = diff % 60;
    if (hours > 0) {
      return '${hours}h ${mins}m';
    }
    return '${mins}m';
  }

  String get formattedCheckInTime {
    if (checkInTime == null) return '';
    final h = checkInTime!.hour % 12 == 0 ? 12 : checkInTime!.hour % 12;
    final m = checkInTime!.minute.toString().padLeft(2, '0');
    final p = checkInTime!.hour >= 12 ? 'PM' : 'AM';
    return '${h.toString().padLeft(2, '0')}:$m $p';
  }
}

/// Service to manage work hours, shift windows, and 8-hour check-out rules.
class WorkHoursService {
  WorkHoursService({
    this.shiftStart = const TimeOfDay(hour: 9, minute: 0),
    this.shiftEnd = const TimeOfDay(hour: 18, minute: 0),
    this.workingWindowEnd = const TimeOfDay(hour: 22, minute: 0),
  });

  /// Standard shift duration (8 hours)
  static const Duration standardShiftLength = Duration(hours: 8);

  final TimeOfDay shiftStart;
  final TimeOfDay shiftEnd;
  final TimeOfDay workingWindowEnd;

  static final WorkHoursService instance = WorkHoursService();

  int _toMinutes(TimeOfDay time) => time.hour * 60 + time.minute;

  bool isWithinWorkingHours([DateTime? time]) {
    final now = time ?? DateTime.now();
    final currentMinutes = now.hour * 60 + now.minute;
    final startMinutes = _toMinutes(shiftStart);
    final windowEndMinutes = _toMinutes(workingWindowEnd);
    return currentMinutes >= startMinutes && currentMinutes <= windowEndMinutes;
  }

  bool isEarlyCheckout([DateTime? time]) {
    final now = time ?? DateTime.now();
    final currentMinutes = now.hour * 60 + now.minute;
    final shiftEndMinutes = _toMinutes(shiftEnd);
    return currentMinutes < shiftEndMinutes;
  }

  String get shiftWindowLabel {
    return '${_formatTimeOfDay(shiftStart)} - ${_formatTimeOfDay(shiftEnd)}';
  }

  String _formatTimeOfDay(TimeOfDay time) {
    final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.period == DayPeriod.am ? 'AM' : 'PM';
    final hourStr = hour.toString().padLeft(2, '0');
    return '$hourStr:$minute $period';
  }

  /// Calculates the employee's current check-in time and duration today.
  Future<EmployeeShiftStatus> getEmployeeShiftStatus(
    int employeeId, {
    DateTime? now,
  }) async {
    final currentTime = now ?? DateTime.now();
    final logs = await LocalLogService.instance.getLogs();

    final todayLogs = logs.where((l) {
      final matchedId = l.payload['matched_employee_id'];
      final ok = l.payload['accepted'] == true;
      return matchedId == employeeId &&
          ok &&
          l.timestamp.year == currentTime.year &&
          l.timestamp.month == currentTime.month &&
          l.timestamp.day == currentTime.day;
    }).toList();

    if (todayLogs.isEmpty) {
      return const EmployeeShiftStatus(
        hasCheckedIn: false,
        workedDuration: Duration.zero,
        isUnder8Hours: false,
      );
    }

    todayLogs.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final lastLog = todayLogs.last;
    final lastPunchType = lastLog.payload['punch_type']?.toString();

    // If the latest punch today was already a check-out, employee is currently OUT
    if (lastPunchType == 'check_out') {
      return const EmployeeShiftStatus(
        hasCheckedIn: false,
        workedDuration: Duration.zero,
        isUnder8Hours: false,
      );
    }

    // Find the current active check-in punch
    final checkInLog = todayLogs.lastWhere(
      (l) => l.payload['punch_type'] == 'check_in',
      orElse: () => todayLogs.first,
    );
    final checkInTime = checkInLog.timestamp;
    final workedDuration = currentTime.difference(checkInTime);
    final isUnder8 = workedDuration.inMinutes < standardShiftLength.inMinutes;

    return EmployeeShiftStatus(
      hasCheckedIn: true,
      checkInTime: checkInTime,
      workedDuration: workedDuration,
      isUnder8Hours: isUnder8,
    );
  }
}
