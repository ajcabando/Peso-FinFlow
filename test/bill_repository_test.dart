import 'package:finflow/core/errors/app_exception.dart';
import 'package:finflow/features/bills/data/repositories/bill_repository_impl.dart';
import 'package:finflow/features/bills/domain/models/bill.dart';
import 'package:finflow/features/bills/domain/repositories/bill_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/test_database.dart';

void main() {
  late TestHarness harness;
  late BillRepository bills;

  setUp(() async {
    harness = await TestHarness.create();
    bills = BillRepositoryImpl(db: harness.db);
  });

  tearDown(() => harness.dispose());

  test('create persists a bill and derives an upcoming status', () async {
    final bill = await bills.create(
      name: 'Internet',
      amountMinor: 150000,
      currencyCode: 'PHP',
      dueDayOfMonth: 28,
      reminderDaysBefore: 3,
    );

    final reloaded = await bills.getById(bill.id);
    expect(reloaded, isNotNull);
    expect(reloaded!.name, 'Internet');
    expect(reloaded.amountMinor, 150000);
    expect(reloaded.dueDayOfMonth, 28);
    expect(reloaded.isActive, isTrue);
    expect(reloaded.lastPaidOn, isNull);

    final status = reloaded.statusOn(DateTime(2026, 1, 1));
    expect(status, BillStatus.upcoming);
  });

  test('a bill due in the past is overdue', () async {
    final bill = await bills.create(
      name: 'Rent',
      amountMinor: 1200000,
      currencyCode: 'PHP',
      dueDayOfMonth: 5,
      reminderDaysBefore: 3,
    );
    expect(bill.statusOn(DateTime(2026, 1, 10)), BillStatus.overdue);
  });

  test('a bill due within the reminder window is due soon', () async {
    final bill = await bills.create(
      name: 'Electricity',
      amountMinor: 220000,
      currencyCode: 'PHP',
      dueDayOfMonth: 7,
      reminderDaysBefore: 3,
    );
    expect(bill.statusOn(DateTime(2026, 1, 5)), BillStatus.dueSoon);
    expect(bill.needsAttention, isTrue);
  });

  test('marking paid records the payment for the current month', () async {
    final bill = await bills.create(
      name: 'Netflix',
      amountMinor: 54900,
      currencyCode: 'PHP',
      dueDayOfMonth: 15,
      reminderDaysBefore: 3,
    );
    final paid = await bills.markPaid(bill.id);
    expect(paid.lastPaidOn, isNotNull);
    final now = DateTime.now();
    expect(paid.statusOn(now), BillStatus.paid);
  });

  test('due dates beyond a month length clamp to the last day', () async {
    final bill = await bills.create(
      name: 'Annual fee',
      amountMinor: 100000,
      currencyCode: 'PHP',
      dueDayOfMonth: 31,
      reminderDaysBefore: 3,
    );
    expect(bill.dueDateIn(DateTime(2026, 2, 1)).day, 28);
  });

  test('update changes editable fields and can pause the bill', () async {
    final bill = await bills.create(
      name: 'Gym',
      amountMinor: 89000,
      currencyCode: 'PHP',
      dueDayOfMonth: 2,
      reminderDaysBefore: 3,
    );
    final updated = await bills.update(
      id: bill.id,
      name: 'Gym Premium',
      amountMinor: 99000,
      currencyCode: 'PHP',
      dueDayOfMonth: 3,
      reminderDaysBefore: 5,
      isActive: false,
    );
    expect(updated.name, 'Gym Premium');
    expect(updated.amountMinor, 99000);
    expect(updated.status, BillStatus.paused);
  });

  test('delete removes the bill', () async {
    final bill = await bills.create(
      name: 'Old subscription',
      amountMinor: 1000,
      currencyCode: 'PHP',
      dueDayOfMonth: 1,
      reminderDaysBefore: 3,
    );
    await bills.deleteBill(bill.id);
    expect(await bills.getById(bill.id), isNull);
  });

  test('validation rejects empty names, non-positive amounts and bad days', () {
    expect(
      () => bills.create(
        name: '  ',
        amountMinor: 100,
        currencyCode: 'PHP',
        dueDayOfMonth: 1,
        reminderDaysBefore: 3,
      ),
      throwsA(isA<ValidationException>()),
    );
    expect(
      () => bills.create(
        name: 'Free',
        amountMinor: 0,
        currencyCode: 'PHP',
        dueDayOfMonth: 1,
        reminderDaysBefore: 3,
      ),
      throwsA(isA<ValidationException>()),
    );
    expect(
      () => bills.create(
        name: 'Bad day',
        amountMinor: 100,
        currencyCode: 'PHP',
        dueDayOfMonth: 32,
        reminderDaysBefore: 3,
      ),
      throwsA(isA<ValidationException>()),
    );
  });

  test('marking paid on a missing bill throws NotFoundException', () {
    expect(
      () => bills.markPaid('missing'),
      throwsA(isA<NotFoundException>()),
    );
  });

  test('watchBills emits the created bill', () async {
    await bills.create(
      name: 'Water',
      amountMinor: 50000,
      currencyCode: 'PHP',
      dueDayOfMonth: 10,
      reminderDaysBefore: 3,
    );
    final list = await harness.db.billDao.watchAll().first;
    expect(list.map((r) => r.name), contains('Water'));
  });
}
