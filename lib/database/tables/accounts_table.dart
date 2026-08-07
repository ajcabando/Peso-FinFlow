import 'package:drift/drift.dart';

import '../../features/accounts/domain/enums/account_kind.dart';
import '../../features/accounts/domain/enums/account_status.dart';
import '../../features/accounts/domain/enums/account_type.dart';
import '../converters/enum_converters.dart';

/// Real accounts, virtual categories and system accounts share this table:
/// everything that can appear in the double-entry ledger lives here.
@DataClassName('AccountRow')
class Accounts extends Table {
  TextColumn get id => text()();

  TextColumn get name => text().withLength(min: 1, max: 120)();

  /// Bank / institution / issuer name (e.g. "BDO", "GCash").
  TextColumn get institution => text().nullable()();

  TextColumn get kind => text().map(enumNameConverter(AccountKind.values))();

  TextColumn get type => text().map(enumNameConverter(AccountType.values))();

  TextColumn get status =>
      text().map(enumNameConverter(AccountStatus.values))();

  /// Informational opening balance. The *authoritative* starting balance is
  /// always recorded in the ledger as an "Opening Balance" transaction, so
  /// balances can never drift from the transaction history.
  IntColumn get openingBalanceMinor => integer()();

  TextColumn get currencyCode => text()();

  /// ARGB colour for icon tiles and charts.
  IntColumn get colorValue => integer()();

  /// Material icon name, stored as text (e.g. `payments`).
  TextColumn get iconCode => text().nullable()();

  TextColumn get notes => text().nullable()();

  IntColumn get sortOrder => integer()();

  /// Hidden accounts are excluded from Net Worth totals.
  BoolColumn get isHidden => boolean()();

  DateTimeColumn get createdAt => dateTime()();

  DateTimeColumn get updatedAt => dateTime()();

  /// Owning cloud user (null = local-only until adopted at sign-in).
  TextColumn get userId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
