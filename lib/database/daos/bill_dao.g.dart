// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'bill_dao.dart';

// ignore_for_file: type=lint
mixin _$BillDaoMixin on DatabaseAccessor<AppDatabase> {
  $AccountsTable get accounts => attachedDatabase.accounts;
  $BillsTable get bills => attachedDatabase.bills;
  BillDaoManager get managers => BillDaoManager(this);
}

class BillDaoManager {
  final _$BillDaoMixin _db;
  BillDaoManager(this._db);
  $$AccountsTableTableManager get accounts =>
      $$AccountsTableTableManager(_db.attachedDatabase, _db.accounts);
  $$BillsTableTableManager get bills =>
      $$BillsTableTableManager(_db.attachedDatabase, _db.bills);
}
