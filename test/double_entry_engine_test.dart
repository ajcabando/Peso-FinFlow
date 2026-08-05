import 'package:finflow/core/errors/app_exception.dart';
import 'package:finflow/features/transactions/domain/engine/double_entry_engine.dart';
import 'package:finflow/features/transactions/domain/engine/transaction_builder.dart';
import 'package:finflow/features/transactions/domain/enums/ledger_direction.dart';
import 'package:finflow/features/transactions/domain/enums/normal_balance_side.dart';
import 'package:finflow/features/transactions/domain/models/draft_transaction.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final occurredAt = DateTime(2026, 8, 4, 12);

  group('TransactionBuilder', () {
    test('expense debits the category and credits the account', () {
      final draft = TransactionBuilder.expense(
        occurredAt: occurredAt,
        currencyCode: 'PHP',
        fromAccountId: 'cash',
        categoryId: 'food',
        amountMinor: 50000,
      );

      expect(draft.type.label, 'Expense');
      expect(draft.amountMinor, 50000);
      expect(draft.entries, hasLength(2));
      expect(draft.entries[0].accountId, 'food');
      expect(draft.entries[0].direction, LedgerDirection.debit);
      expect(draft.entries[1].accountId, 'cash');
      expect(draft.entries[1].direction, LedgerDirection.credit);
    });

    test('income debits the account and credits the category', () {
      final draft = TransactionBuilder.income(
        occurredAt: occurredAt,
        currencyCode: 'PHP',
        toAccountId: 'bank',
        categoryId: 'salary',
        amountMinor: 3000000,
      );

      expect(draft.entries[0].accountId, 'bank');
      expect(draft.entries[0].direction, LedgerDirection.debit);
      expect(draft.entries[1].accountId, 'salary');
      expect(draft.entries[1].direction, LedgerDirection.credit);
    });

    test('transfer has no category and moves money between accounts', () {
      final draft = TransactionBuilder.transfer(
        occurredAt: occurredAt,
        currencyCode: 'PHP',
        fromAccountId: 'cash',
        toAccountId: 'gcash',
        amountMinor: 100000,
      );

      expect(draft.type.label, 'Transfer');
      expect(draft.entries, hasLength(2));
      expect(draft.entries[0].accountId, 'gcash');
      expect(draft.entries[0].direction, LedgerDirection.debit);
      expect(draft.entries[1].accountId, 'cash');
      expect(draft.entries[1].direction, LedgerDirection.credit);
    });

    test('credit card purchase behaves like an expense', () {
      final draft = TransactionBuilder.creditCardPurchase(
        occurredAt: occurredAt,
        currencyCode: 'PHP',
        creditCardAccountId: 'visa',
        categoryId: 'groceries',
        amountMinor: 200000,
      );

      expect(draft.type.label, 'Expense');
      // Category debited...
      expect(draft.entries[0].accountId, 'groceries');
      expect(draft.entries[0].direction, LedgerDirection.debit);
      // ...credit card (liability) credited => balance goes up.
      expect(draft.entries[1].accountId, 'visa');
      expect(draft.entries[1].direction, LedgerDirection.credit);
    });

    test('credit card payment is a transfer from the bank', () {
      final draft = TransactionBuilder.creditCardPayment(
        occurredAt: occurredAt,
        currencyCode: 'PHP',
        bankAccountId: 'bank',
        creditCardAccountId: 'visa',
        amountMinor: 150000,
      );

      expect(draft.type.label, 'Transfer');
      expect(draft.entries[0].accountId, 'visa');
      expect(draft.entries[0].direction, LedgerDirection.debit);
      expect(draft.entries[1].accountId, 'bank');
      expect(draft.entries[1].direction, LedgerDirection.credit);
    });

    test('a refund is typed as a refund and credits the category', () {
      final draft = TransactionBuilder.refund(
        occurredAt: occurredAt,
        currencyCode: 'PHP',
        toAccountId: 'cash',
        categoryId: 'food',
        amountMinor: 25000,
      );

      expect(draft.type.label, 'Refund');
      expect(draft.entries[0].accountId, 'cash');
      expect(draft.entries[0].direction, LedgerDirection.debit);
      expect(draft.entries[1].accountId, 'food');
      expect(draft.entries[1].direction, LedgerDirection.credit);
    });

    test('opening balance is balanced against the system account', () {
      final draft = TransactionBuilder.openingBalance(
        occurredAt: occurredAt,
        currencyCode: 'PHP',
        accountId: 'new-account',
        openingBalancesAccountId: 'opening',
        amountMinor: 50000,
        accountNormalSide: NormalBalanceSide.debit,
      );

      expect(draft.entries[0].accountId, 'new-account');
      expect(draft.entries[0].direction, LedgerDirection.debit);
      expect(draft.entries[1].accountId, 'opening');
      expect(draft.entries[1].direction, LedgerDirection.credit);
    });
  });

  group('DoubleEntryEngine.validate', () {
    test('accepts a balanced draft', () {
      final draft = TransactionBuilder.transfer(
        occurredAt: occurredAt,
        currencyCode: 'PHP',
        fromAccountId: 'a',
        toAccountId: 'b',
        amountMinor: 1000,
      );
      expect(() => DoubleEntryEngine.validate(draft), returnsNormally);
    });

    test('rejects an unbalanced draft', () {
      final base = TransactionBuilder.expense(
        occurredAt: occurredAt,
        currencyCode: 'PHP',
        fromAccountId: 'a',
        categoryId: 'food',
        amountMinor: 1000,
      );
      // Keep only the debit leg — the credit is missing.
      final unbalanced = base.copyWith(entries: [base.entries[0]]);
      expect(
        () => DoubleEntryEngine.validate(unbalanced),
        throwsA(isA<ValidationException>()),
      );
    });

    test('rejects non-positive amounts', () {
      final base = TransactionBuilder.transfer(
        occurredAt: occurredAt,
        currencyCode: 'PHP',
        fromAccountId: 'a',
        toAccountId: 'b',
        amountMinor: 1000,
      );
      final draft = base.copyWith(
        entries: [
          base.entries[0],
          const DraftEntry(
            accountId: 'b',
            direction: LedgerDirection.credit,
            amountMinor: -1000,
          ),
        ],
      );
      expect(
        () => DoubleEntryEngine.validate(draft),
        throwsA(isA<ValidationException>()),
      );
    });

    test('rejects a self-transfer (same account twice)', () {
      final base = TransactionBuilder.transfer(
        occurredAt: occurredAt,
        currencyCode: 'PHP',
        fromAccountId: 'a',
        toAccountId: 'b',
        amountMinor: 1000,
      );
      // Both legs on the same account — invalid.
      final draft = base.copyWith(
        entries: [
          const DraftEntry(
            accountId: 'a',
            direction: LedgerDirection.debit,
            amountMinor: 1000,
          ),
          const DraftEntry(
            accountId: 'a',
            direction: LedgerDirection.credit,
            amountMinor: 1000,
          ),
        ],
      );
      expect(
        () => DoubleEntryEngine.validate(draft),
        throwsA(isA<ValidationException>()),
      );
    });

    test('rejects drafts with fewer than two entries', () {
      final base = TransactionBuilder.transfer(
        occurredAt: occurredAt,
        currencyCode: 'PHP',
        fromAccountId: 'a',
        toAccountId: 'b',
        amountMinor: 1000,
      );
      final draft = base.copyWith(entries: [base.entries[0]]);
      expect(
        () => DoubleEntryEngine.validate(draft),
        throwsA(isA<ValidationException>()),
      );
    });
  });

  group('DoubleEntryEngine.netEffect', () {
    test('debit-normal accounts: debits increase, credits decrease', () {
      final entries = [
        (direction: LedgerDirection.debit, amountMinor: 1000),
        (direction: LedgerDirection.credit, amountMinor: 300),
      ];
      expect(
        DoubleEntryEngine.netEffect(NormalBalanceSide.debit, entries),
        700,
      );
    });

    test('credit-normal accounts (credit cards): credits increase', () {
      final entries = [
        (direction: LedgerDirection.debit, amountMinor: 500),
        (direction: LedgerDirection.credit, amountMinor: 2000),
      ];
      expect(
        DoubleEntryEngine.netEffect(NormalBalanceSide.credit, entries),
        1500,
      );
    });

    test('income categories accumulate credits (income earned)', () {
      final entries = [
        (direction: LedgerDirection.credit, amountMinor: 500000),
      ];
      expect(
        DoubleEntryEngine.netEffect(NormalBalanceSide.credit, entries),
        500000,
      );
    });

    test('expense categories accumulate debits (money spent)', () {
      final entries = [(direction: LedgerDirection.debit, amountMinor: 30000)];
      expect(
        DoubleEntryEngine.netEffect(NormalBalanceSide.debit, entries),
        30000,
      );
    });
  });
}
