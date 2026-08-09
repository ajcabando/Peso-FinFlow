import '../../../../database/app_database.dart';

/// Builds the snake_case wire payloads (docs/BACKEND_API.md §4) that the
/// operation log carries. Each mirrors the local Drift row 1:1 plus the
/// transaction children (`ledgerEntries`, `transactionTags`) as a consistent
/// set — the same shape the server materialiser persists.
abstract final class SyncPayloads {
  static Map<String, dynamic> account(AccountRow row) => {
    'id': row.id,
    'name': row.name,
    'institution': row.institution,
    'kind': row.kind.name,
    'type': row.type.name,
    'status': row.status.name,
    'opening_balance_minor': row.openingBalanceMinor,
    'currency_code': row.currencyCode,
    'color_value': row.colorValue,
    'icon_code': row.iconCode,
    'notes': row.notes,
    'sort_order': row.sortOrder,
    'is_hidden': row.isHidden,
    'version': row.version,
    'created_at': _iso(row.createdAt),
    'updated_at': _iso(row.updatedAt),
    'deleted_at': null,
  };

  static Map<String, dynamic> tag(TagRow row) => {
    'id': row.id,
    'name': row.name,
    'color_value': row.colorValue,
    'version': row.version,
    'created_at': _iso(row.createdAt),
    'updated_at': _iso(row.updatedAt ?? row.createdAt),
    'deleted_at': null,
  };

  static Map<String, dynamic> transaction({
    required TransactionRow row,
    required List<LedgerEntryRow> entries,
    required List<TransactionTagRow> tagLinks,
  }) => {
    'id': row.id,
    'type': row.type.name,
    'amount_minor': row.amountMinor,
    'currency_code': row.currencyCode,
    'occurred_at': _iso(row.occurredAt),
    'note': row.note,
    'merchant': row.merchant,
    'reference_number': row.referenceNumber,
    'location': row.location,
    'version': row.version,
    'created_at': _iso(row.createdAt),
    'updated_at': _iso(row.updatedAt),
    'deleted_at': null,
    'ledgerEntries': [
      for (final e in entries)
        {
          'id': e.id,
          'account_id': e.accountId,
          'direction': e.direction.name,
          'amount_minor': e.amountMinor,
          'currency_code': e.currencyCode,
        },
    ],
    'transactionTags': [
      for (final t in tagLinks) {'tag_id': t.tagId},
    ],
  };

  static Map<String, dynamic> bill(BillRow row) => {
    'id': row.id,
    'name': row.name,
    'amount_minor': row.amountMinor,
    'currency_code': row.currencyCode,
    'account_id': row.accountId,
    'due_day_of_month': row.dueDayOfMonth,
    'reminder_days_before': row.reminderDaysBefore,
    'is_active': row.isActive,
    'last_paid_on': row.lastPaidOn == null ? null : _iso(row.lastPaidOn!),
    'version': row.version,
    'created_at': _iso(row.createdAt),
    'updated_at': _iso(row.updatedAt),
    'deleted_at': null,
  };

  static Map<String, dynamic> budget(BudgetRow row) => {
    'id': row.id,
    'category_id': row.categoryId,
    'amount_minor': row.amountMinor,
    'currency_code': row.currencyCode,
    'version': row.version,
    'created_at': _iso(row.createdAt),
    'updated_at': _iso(row.updatedAt),
    'deleted_at': null,
  };

  static Map<String, dynamic> appSetting(AppSettingRow row) => {
    'key': row.key,
    'value': row.value,
    'version': row.version,
    'updated_at': _iso(row.updatedAt ?? DateTime.now()),
    'deleted_at': null,
  };

  static String _iso(DateTime value) => value.toUtc().toIso8601String();
}
