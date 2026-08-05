import 'package:intl/intl.dart';

/// Convenience date formatting helpers used across the UI.
extension DateTimeFormatting on DateTime {
  /// e.g. `Aug 4, 2026`
  String get monthDayYear => DateFormat('MMM d, y').format(this);

  /// e.g. `Tuesday, Aug 4`
  String get weekdayMonthDay => DateFormat('EEEE, MMM d').format(this);

  /// e.g. `Aug 4`
  String get monthDay => DateFormat('MMM d').format(this);

  /// e.g. `August 2026`
  String get monthYear => DateFormat('MMMM yyyy').format(this);

  /// e.g. `2:30 PM`
  String get hourMinute => DateFormat('h:mm a').format(this);

  /// True when [other] falls on the same calendar day as this date.
  bool isSameDay(DateTime other) =>
      year == other.year && month == other.month && day == other.day;
}
