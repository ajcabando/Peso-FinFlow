import 'package:supabase_flutter/supabase_flutter.dart';

import 'sync_remote.dart';

/// [SyncRemote] backed by Supabase PostgREST.
///
/// Row-level security scopes every query to the signed-in user, so no
/// `user_id` filter is needed here — the engine only ever talks to the
/// current user's own rows.
class SupabaseSyncRemote implements SyncRemote {
  SupabaseSyncRemote({required SupabaseClient client}) : this._(client);

  SupabaseSyncRemote._(this._client);

  final SupabaseClient _client;

  static const _primaryKey = {
    'accounts': 'id',
    'transactions': 'id',
    'ledger_entries': 'id',
    'tags': 'id',
    'transaction_tags': 'transaction_id,tag_id',
    'bills': 'id',
    'budgets': 'id',
    'app_settings': 'key',
  };

  String _pk(String table) => _primaryKey[table] ?? 'id';

  @override
  Future<List<Map<String, dynamic>>> fetchChanged(
    String table, {
    required DateTime since,
    int limit = 1000,
  }) async {
    final response = await _client
        .from(table)
        .select()
        .gt('updated_at', since.toUtc().toIso8601String())
        .order('updated_at')
        .limit(limit);
    return _maps(response);
  }

  @override
  Future<Map<String, DateTime>> fetchUpdatedAt(
    String table,
    List<String> ids,
  ) async {
    if (ids.isEmpty) return const {};
    final pk = _pk(table);
    final response = await _client
        .from(table)
        .select('$pk,updated_at')
        .inFilter(pk, ids);
    return {
      for (final row in _maps(response))
        if (row['updated_at'] != null && row[pk] != null)
          row[pk] as String: DateTime.parse(row['updated_at'] as String),
    };
  }

  @override
  Future<void> upsert(
    String table,
    List<Map<String, dynamic>> rows, {
    required String onConflict,
  }) async {
    if (rows.isEmpty) return;
    await _client.from(table).upsert(rows, onConflict: onConflict);
  }

  @override
  Future<void> replaceTransactionChildren(
    String transactionId, {
    required List<Map<String, dynamic>> ledgerEntries,
    required List<Map<String, dynamic>> transactionTags,
  }) async {
    await _client
        .from('ledger_entries')
        .delete()
        .eq('transaction_id', transactionId);
    if (ledgerEntries.isNotEmpty) {
      await _client
          .from('ledger_entries')
          .upsert(ledgerEntries, onConflict: 'id');
    }
    await _client
        .from('transaction_tags')
        .delete()
        .eq('transaction_id', transactionId);
    if (transactionTags.isNotEmpty) {
      await _client
          .from('transaction_tags')
          .upsert(transactionTags, onConflict: 'transaction_id,tag_id');
    }
  }

  @override
  Future<Map<String, TransactionChildren>> fetchTransactionChildren(
    List<String> transactionIds,
  ) async {
    if (transactionIds.isEmpty) return const {};
    final entries = await _client
        .from('ledger_entries')
        .select()
        .inFilter('transaction_id', transactionIds);
    final tags = await _client
        .from('transaction_tags')
        .select()
        .inFilter('transaction_id', transactionIds);

    final result = <String, TransactionChildren>{
      for (final id in transactionIds)
        id: TransactionChildren(),
    };
    for (final row in _maps(entries)) {
      final txId = row['transaction_id'] as String;
      result[txId] ??= TransactionChildren();
      result[txId] = TransactionChildren(
        ledgerEntries: [...result[txId]!.ledgerEntries, row],
        transactionTags: result[txId]!.transactionTags,
      );
    }
    for (final row in _maps(tags)) {
      final txId = row['transaction_id'] as String;
      result[txId] ??= TransactionChildren();
      result[txId] = TransactionChildren(
        ledgerEntries: result[txId]!.ledgerEntries,
        transactionTags: [...result[txId]!.transactionTags, row],
      );
    }
    return result;
  }

  static List<Map<String, dynamic>> _maps(List<dynamic> response) =>
      [for (final row in response) Map<String, dynamic>.from(row as Map)];
}
