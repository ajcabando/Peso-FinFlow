import 'package:drift/drift.dart';

import '../../../../core/errors/app_exception.dart';
import '../../../../core/utils/id_generator.dart';
import '../../../../database/app_database.dart';
import '../../domain/models/bill.dart';
import '../../domain/repositories/bill_repository.dart';

/// Persists recurring bills with ledger-independent lifecycle tracking.
class BillRepositoryImpl implements BillRepository {
  // ignore: prefer_initializing_formals
  BillRepositoryImpl({required AppDatabase db}) : _db = db;

  final AppDatabase _db;

  @override
  Stream<List<Bill>> watchBills() =>
      _db.billDao.watchAll().map((rows) => rows.map(Bill.fromRow).toList());

  @override
  Future<Bill?> getById(String id) async {
    final row = await _db.billDao.getById(id);
    return row == null ? null : Bill.fromRow(row);
  }

  @override
  Future<Bill> create({
    required String name,
    required int amountMinor,
    required String currencyCode,
    String? accountId,
    required int dueDayOfMonth,
    required int reminderDaysBefore,
  }) async {
    _validate(
      name: name,
      amountMinor: amountMinor,
      dueDayOfMonth: dueDayOfMonth,
      reminderDaysBefore: reminderDaysBefore,
    );
    final now = DateTime.now();
    final id = IdGenerator.next();
    await _db.billDao.insert(
      BillsCompanion.insert(
        id: id,
        name: name.trim(),
        amountMinor: amountMinor,
        currencyCode: currencyCode,
        accountId: Value(accountId),
        dueDayOfMonth: Value(dueDayOfMonth),
        reminderDaysBefore: Value(reminderDaysBefore),
        createdAt: now,
        updatedAt: now,
      ),
    );
    return (await getById(id))!;
  }

  @override
  Future<Bill> update({
    required String id,
    required String name,
    required int amountMinor,
    required String currencyCode,
    String? accountId,
    required int dueDayOfMonth,
    required int reminderDaysBefore,
    required bool isActive,
  }) async {
    _validate(
      name: name,
      amountMinor: amountMinor,
      dueDayOfMonth: dueDayOfMonth,
      reminderDaysBefore: reminderDaysBefore,
    );
    final existing = await _db.billDao.getById(id);
    if (existing == null) {
      throw const NotFoundException('Bill not found.');
    }
    await _db.billDao.updateRow(
      BillsCompanion(
        id: Value(id),
        name: Value(name.trim()),
        amountMinor: Value(amountMinor),
        currencyCode: Value(currencyCode),
        accountId: Value(accountId),
        dueDayOfMonth: Value(dueDayOfMonth),
        reminderDaysBefore: Value(reminderDaysBefore),
        isActive: Value(isActive),
        updatedAt: Value(DateTime.now()),
      ),
    );
    return (await getById(id))!;
  }

  @override
  Future<Bill> markPaid(String id) async {
    final existing = await _db.billDao.getById(id);
    if (existing == null) {
      throw const NotFoundException('Bill not found.');
    }
    await _db.billDao.updateRow(
      BillsCompanion(
        id: Value(id),
        lastPaidOn: Value(DateTime.now()),
        updatedAt: Value(DateTime.now()),
      ),
    );
    return (await getById(id))!;
  }

  @override
  Future<void> deleteBill(String id) async {
    final existing = await _db.billDao.getById(id);
    if (existing == null) {
      throw const NotFoundException('Bill not found.');
    }
    await _db.billDao.deleteById(id);
  }

  void _validate({
    required String name,
    required int amountMinor,
    required int dueDayOfMonth,
    required int reminderDaysBefore,
  }) {
    if (name.trim().isEmpty) {
      throw const ValidationException('A bill needs a name.');
    }
    if (amountMinor <= 0) {
      throw const ValidationException('The bill amount must be positive.');
    }
    if (dueDayOfMonth < 1 || dueDayOfMonth > 31) {
      throw const ValidationException('The due day must be between 1 and 31.');
    }
    if (reminderDaysBefore < 0) {
      throw const ValidationException('Reminder days cannot be negative.');
    }
  }
}
