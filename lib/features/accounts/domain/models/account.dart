import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../database/app_database.dart';
import '../../../transactions/domain/enums/normal_balance_side.dart';
import '../enums/account_kind.dart';
import '../enums/account_status.dart';
import '../enums/account_type.dart';

/// An account (or virtual category) in the FinFlow ledger.
class Account {
  const Account({
    required this.id,
    required this.name,
    required this.kind,
    required this.type,
    required this.status,
    required this.openingBalanceMinor,
    required this.currencyCode,
    required this.colorValue,
    required this.isHidden,
    required this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
    this.institution,
    this.iconCode,
    this.notes,
  });

  factory Account.fromRow(AccountRow row) => Account(
    id: row.id,
    name: row.name,
    institution: row.institution,
    kind: row.kind,
    type: row.type,
    status: row.status,
    openingBalanceMinor: row.openingBalanceMinor,
    currencyCode: row.currencyCode,
    colorValue: row.colorValue,
    iconCode: row.iconCode,
    notes: row.notes,
    sortOrder: row.sortOrder,
    isHidden: row.isHidden,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
  );

  final String id;
  final String name;
  final String? institution;
  final AccountKind kind;
  final AccountType type;
  final AccountStatus status;
  final int openingBalanceMinor;
  final String currencyCode;
  final int colorValue;
  final String? iconCode;
  final String? notes;
  final int sortOrder;
  final bool isHidden;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// True for categories and system accounts (not real financial accounts).
  bool get isVirtual => kind.isVirtual;

  /// Ledger side on which this account records increases.
  NormalBalanceSide get normalBalanceSide => type.normalBalanceSide;

  /// Material [Color] for icon tiles and charts.
  Color get color => Color(colorValue);

  /// Default color used when creating a new account.
  static int defaultColorValue() => AppColors.brand.toARGB32();

  /// Picks a distinct colour for a new account or category based on the
  /// colours already in use by [existing]: the least-used palette colour
  /// wins (ties go to the earlier palette entry), so consecutive accounts
  /// or categories stay visually distinct instead of all defaulting to the
  /// same brand purple.
  static int dynamicColorValue(List<Account> existing) {
    final counts = <int, int>{};
    for (final account in existing) {
      counts[account.colorValue] = (counts[account.colorValue] ?? 0) + 1;
    }

    var best = AppColors.accountPalette.first.toARGB32();
    var bestCount = 1 << 30;
    for (final paletteColor in AppColors.accountPalette) {
      final value = paletteColor.toARGB32();
      final count = counts[value] ?? 0;
      if (count < bestCount) {
        best = value;
        bestCount = count;
      }
    }
    return best;
  }
}
