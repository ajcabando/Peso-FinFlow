import '../../../../database/app_database.dart';

/// A recurring monthly bill, subscription or scheduled obligation.
///
/// Bills are reminders (not ledger entries): money still flows through
/// ordinary transactions. The [status] is derived from the current date and
/// [lastPaidOn], so it is always consistent with "today".
class Bill {
  const Bill({
    required this.id,
    required this.name,
    required this.amountMinor,
    required this.currencyCode,
    required this.dueDayOfMonth,
    required this.reminderDaysBefore,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
    this.accountId,
    this.lastPaidOn,
  });

  factory Bill.fromRow(BillRow row) => Bill(
    id: row.id,
    name: row.name,
    amountMinor: row.amountMinor,
    currencyCode: row.currencyCode,
    accountId: row.accountId,
    dueDayOfMonth: row.dueDayOfMonth,
    reminderDaysBefore: row.reminderDaysBefore,
    isActive: row.isActive,
    lastPaidOn: row.lastPaidOn,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
  );

  final String id;
  final String name;

  /// Amount due each period in minor units.
  final int amountMinor;

  final String currencyCode;

  /// The account this bill is usually paid from, if any.
  final String? accountId;

  /// Day of the month the bill is due (1–31; days past a month's length
  /// clamp to that month's last day).
  final int dueDayOfMonth;

  /// How many days before the due date the reminder kicks in.
  final int reminderDaysBefore;

  final bool isActive;

  /// The most recent month this bill was marked as paid.
  final DateTime? lastPaidOn;

  final DateTime createdAt;
  final DateTime updatedAt;

  /// The due date in [now]'s month (clamped to the month's last day).
  DateTime dueDateIn(DateTime now) {
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    return DateTime(
      now.year,
      now.month,
      dueDayOfMonth.clamp(1, daysInMonth),
    );
  }

  /// The current status of the bill relative to [now].
  BillStatus get status {
    final now = DateTime.now();
    return statusOn(now);
  }

  /// The current status of the bill relative to [now].
  BillStatus statusOn(DateTime now) {
    if (!isActive) return BillStatus.paused;

    final paidThisMonth =
        lastPaidOn != null &&
        lastPaidOn!.year == now.year &&
        lastPaidOn!.month == now.month;
    if (paidThisMonth) return BillStatus.paid;

    final due = dueDateIn(now);
    final dueDay = DateTime(now.year, now.month, due.day);
    final today = DateTime(now.year, now.month, now.day);

    final daysUntil = dueDay.difference(today).inDays;
    if (daysUntil < 0) return BillStatus.overdue;
    if (daysUntil <= reminderDaysBefore) return BillStatus.dueSoon;
    return BillStatus.upcoming;
  }

  /// Whether the bill needs attention right now (overdue or due soon).
  bool get needsAttention => status.needsAttention;

  Bill copyWith({DateTime? lastPaidOn}) => Bill(
    id: id,
    name: name,
    amountMinor: amountMinor,
    currencyCode: currencyCode,
    accountId: accountId,
    dueDayOfMonth: dueDayOfMonth,
    reminderDaysBefore: reminderDaysBefore,
    isActive: isActive,
    lastPaidOn: lastPaidOn ?? this.lastPaidOn,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

/// The derived attention state of a [Bill] for the current month.
enum BillStatus {
  /// Payment is overdue this month.
  overdue,

  /// Due within [Bill.reminderDaysBefore] days of the due date.
  dueSoon,

  /// Marked as paid this month.
  paid,

  /// Active but not due for a while.
  upcoming,

  /// Turned off (cancelled subscription, archived obligation).
  paused,
}

extension BillStatusX on BillStatus {
  bool get needsAttention =>
      this == BillStatus.overdue || this == BillStatus.dueSoon;
}
