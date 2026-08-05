import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/bills_table.dart';

part 'bill_dao.g.dart';

/// Data access for [Bills].
@DriftAccessor(tables: [Bills])
class BillDao extends DatabaseAccessor<AppDatabase> with _$BillDaoMixin {
  BillDao(super.db);

  Stream<List<BillRow>> watchAll() => (select(
    bills,
  )..orderBy([(t) => OrderingTerm(expression: t.dueDayOfMonth)])).watch();

  Future<List<BillRow>> getAll() => (select(
    bills,
  )..orderBy([(t) => OrderingTerm(expression: t.dueDayOfMonth)])).get();

  Future<BillRow?> getById(String id) =>
      (select(bills)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<void> insert(BillsCompanion row) => into(bills).insert(row);

  Future<void> updateRow(BillsCompanion row) =>
      (update(bills)..where((t) => t.id.equals(row.id.value))).write(row);

  Future<void> deleteById(String id) =>
      (delete(bills)..where((t) => t.id.equals(id))).go();
}
