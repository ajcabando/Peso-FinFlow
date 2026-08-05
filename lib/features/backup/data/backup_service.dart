import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../database/app_database.dart';
import '../../../database/tables/accounts_table.dart';
import '../../../database/tables/app_settings_table.dart';
import '../../../database/tables/attachments_table.dart';
import '../../../database/tables/bills_table.dart';
import '../../../database/tables/budgets_table.dart';
import '../../../database/tables/ledger_entries_table.dart';
import '../../../database/tables/tags_table.dart';
import '../../../database/tables/transaction_tags_table.dart';
import '../../../database/tables/transactions_table.dart';
import '../../../features/accounts/domain/enums/account_kind.dart';
import '../../../features/accounts/domain/enums/account_status.dart';
import '../../../features/accounts/domain/enums/account_type.dart';
import '../../../features/transactions/domain/enums/ledger_direction.dart';
import '../../../features/transactions/domain/enums/transaction_type.dart';

/// Full-database backup and restore as a portable JSON snapshot.
///
/// Every table is exported as an ordered list of row maps; restoring clears
/// the database and replays them inside one transaction (parents before
/// children, children deleted before parents). The file is plain UTF-8 JSON,
/// so it works identically on native, desktop and the WASM web build — and
/// stays human-inspectable.
class BackupService {
  // ignore: prefer_initializing_formals
  BackupService({required AppDatabase db}) : _db = db;

  final AppDatabase _db;

  static const String _formatMarker = 'finflow-backup';
  static const int _formatVersion = 1;

/// Serialises the entire database to a portable JSON blob.
  Future<Uint8List> exportBackup() async {
    final tables = <String, List<Map<String, Object?>>>{
      'accounts': await _exportRows(_db.accounts),
      'transactions': await _exportRows(_db.transactions),
      'tags': await _exportRows(_db.tags),
      'ledger_entries': await _exportRows(_db.ledgerEntries),
      'transaction_tags': await _exportRows(_db.transactionTags),
      'attachments': await _exportRows(_db.attachments),
      'app_settings': await _exportRows(_db.appSettings),
      'budgets': await _exportRows(_db.budgets),
      'bills': await _exportRows(_db.bills),
    };

    final json = jsonEncode({
      'format': _formatMarker,
      'version': _formatVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'tables': tables,
    });
    return Uint8List.fromList(utf8.encode(json));
  }

  Future<List<Map<String, Object?>>> _exportRows<T extends Table, D extends DataClass>(
    TableInfo<T, D> table,
  ) async {
    final rows = await _db.select(table).get();
    return rows.map((row) => row.toJson(serializer: _portable)).toList();
  }

  /// Replaces the current database contents with [bytes] (from
  /// [exportBackup]). Existing data is overwritten atomically.
  Future<void> importBackup(Uint8List bytes) async {
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Not a FinFlow backup file.');
    }
    if (decoded['format'] != _formatMarker) {
      throw const FormatException('Not a FinFlow backup file.');
    }
    final tables = decoded['tables'];
    if (tables is! Map<String, dynamic>) {
      throw const FormatException('Backup is missing its table data.');
    }

    await _db.transaction(() async {
      // Children first, then parents (foreign keys are enforced).
      await _deleteRows(_db.transactionTags);
      await _deleteRows(_db.ledgerEntries);
      await _deleteRows(_db.attachments);
      await _deleteRows(_db.tags);
      await _deleteRows(_db.transactions);
      await _deleteRows(_db.bills);
      await _deleteRows(_db.budgets);
      await _deleteRows(_db.accounts);
      await _deleteRows(_db.appSettings);

      // Parents first, then children.
      await _importRows(_db.accounts, tables['accounts']);
      await _importRows(_db.transactions, tables['transactions']);
      await _importRows(_db.tags, tables['tags']);
      await _importRows(_db.ledgerEntries, tables['ledger_entries']);
      await _importRows(_db.transactionTags, tables['transaction_tags']);
      await _importRows(_db.attachments, tables['attachments']);
      await _importRows(_db.appSettings, tables['app_settings']);
      await _importRows(_db.budgets, tables['budgets']);
      await _importRows(_db.bills, tables['bills']);
    });
  }

  Future<void> _deleteRows<T extends Table, D extends DataClass>(
    TableInfo<T, D> table,
  ) async {
    await _db.delete(table).go();
  }

  Future<void> _importRows<T extends Table, D extends DataClass>(
    TableInfo<T, D> table,
    Object? rows,
  ) async {
    if (rows is! List) return;
    for (final row in rows) {
      if (row is! Map<String, dynamic>) continue;
      final instance = _fromJson(table, row);
      // Every generated row class implements `Insertable`, so this cast is
      // safe for all nine tables.
      await _db.into(table).insert(instance as Insertable<D>);
    }
  }

  /// Calls the generated `fromJson` factory of the table's data class.
  D _fromJson<T extends Table, D extends DataClass>(
    TableInfo<T, D> table,
    Map<String, dynamic> json,
  ) {
    return switch (table) {
      Accounts() => AccountRow.fromJson(json, serializer: _portable) as D,
      Transactions() => TransactionRow.fromJson(json, serializer: _portable) as D,
      Tags() => TagRow.fromJson(json, serializer: _portable) as D,
      LedgerEntries() =>
        LedgerEntryRow.fromJson(json, serializer: _portable) as D,
      TransactionTags() =>
        TransactionTagRow.fromJson(json, serializer: _portable) as D,
      Attachments() => AttachmentRow.fromJson(json, serializer: _portable) as D,
      AppSettings() => AppSettingRow.fromJson(json, serializer: _portable) as D,
      Budgets() => BudgetRow.fromJson(json, serializer: _portable) as D,
      Bills() => BillRow.fromJson(json, serializer: _portable) as D,
      _ => throw StateError('Unsupported table: ${table.actualTableName}'),
    };
  }

  /// Round-trips the values drift's default serializer can't encode: enums
  /// become their `.name` and date-times their ISO-8601 string, keeping the
  /// backup file human-readable.
  static const ValueSerializer _portable = _PortableSerializer();
}

class _PortableSerializer extends ValueSerializer {
  const _PortableSerializer();

  @override
  dynamic toJson<T>(T value) {
    if (value == null) return null;
    if (value is Enum) return value.name;
    if (value is DateTime) return value.toIso8601String();
    return value;
  }

  @override
  T fromJson<T>(dynamic json) {
    if (json == null) return null as T;
    if (T == AccountKind) return AccountKind.values.byName(json as String) as T;
    if (T == AccountType) return AccountType.values.byName(json as String) as T;
    if (T == AccountStatus) {
      return AccountStatus.values.byName(json as String) as T;
    }
    if (T == TransactionType) {
      return TransactionType.values.byName(json as String) as T;
    }
    if (T == LedgerDirection) {
      return LedgerDirection.values.byName(json as String) as T;
    }
    if (T == DateTime) return DateTime.parse(json as String) as T;
    return json as T;
  }
}
