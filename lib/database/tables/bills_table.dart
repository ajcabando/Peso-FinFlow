import 'package:drift/drift.dart';

import 'accounts_table.dart';

/// A recurring monthly bill, subscription or other scheduled obligation.
///
/// Bills are *reminders*, not ledger entries: the money moving still flows
/// through ordinary transactions (optionally from a linked [accountId]). The
/// app tracks when each bill is due so it can surface what needs attention.
@DataClassName('BillRow')
class Bills extends Table {
  TextColumn get id => text()();

  TextColumn get name => text().withLength(min: 1, max: 120)();

  /// Amount due each period in minor units.
  IntColumn get amountMinor => integer()();

  TextColumn get currencyCode => text()();

  /// The account this bill is usually paid from, if any.
  TextColumn get accountId =>
      text().nullable().references(Accounts, #id, onDelete: KeyAction.setNull)();

  /// Day of the month the bill is due (1–31; days past a month's length
  /// clamp to that month's last day).
  IntColumn get dueDayOfMonth => integer().withDefault(const Constant(1))();

  /// How many days before the due date the reminder kicks in.
  IntColumn get reminderDaysBefore =>
      integer().withDefault(const Constant(3))();

  /// Toggles the bill on/off (e.g. a cancelled subscription is kept for
  /// history but no longer reminds).
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  /// The most recent month this bill was marked as paid. `null` means it has
  /// never been paid (or the last payment predates tracking).
  DateTimeColumn get lastPaidOn => dateTime().nullable()();

  DateTimeColumn get createdAt => dateTime()();

  DateTimeColumn get updatedAt => dateTime()();

  /// Owning cloud user (null = local-only until adopted at sign-in).
  TextColumn get userId => text().nullable()();

  /// Operation-log CAS version (schema v5). 0 = never synced; bumped by every
  /// repository write while signed in.
  IntColumn get version => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}
