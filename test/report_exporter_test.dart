import 'package:finflow/features/reports/data/report_exporter.dart';
import 'package:finflow/features/transactions/domain/enums/transaction_type.dart';
import 'package:finflow/features/transactions/domain/models/category_spend.dart';
import 'package:finflow/features/transactions/domain/models/financial_transaction.dart';
import 'package:finflow/features/transactions/domain/models/transaction_context.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  FinancialTransaction tx({
    required String id,
    required TransactionType type,
    required int amountMinor,
    String? merchant,
    String? note,
    DateTime? occurredAt,
  }) => FinancialTransaction(
    id: id,
    type: type,
    amountMinor: amountMinor,
    currencyCode: 'PHP',
    occurredAt: occurredAt ?? DateTime(2026, 7, 15),
    createdAt: DateTime(2026, 7, 15),
    updatedAt: DateTime(2026, 7, 15),
    merchant: merchant,
    note: note,
  );

  ReportData reportWith(List<TransactionContext> contexts) => ReportData(
    from: DateTime(2026, 7, 1),
    to: DateTime(2026, 8, 1),
    currencyCode: 'PHP',
    incomeMinor: 300000,
    expenseMinor: 125000,
    categories: const [
      CategorySpend(
        categoryId: 'c1',
        categoryName: 'Food & Dining',
        amountMinor: 75000,
        isIncome: false,
        colorValue: 0xFF4E9BFF,
      ),
    ],
    contexts: contexts,
  );

  test('CSV contains the header block and one row per transaction', () {
    final csv = ReportExporter.buildCsv(
      reportWith([
        TransactionContext(
          transaction: tx(
            id: 't1',
            type: TransactionType.expense,
            amountMinor: 123456,
            merchant: 'Jollibee',
          ),
          accountName: 'Cash',
          categoryName: 'Food & Dining',
        ),
      ]),
    );

    expect(csv, contains('FinFlow transaction report'));
    expect(csv, contains('Period,2026-07-01 to 2026-08-01'));
    expect(csv, contains('Income,₱3,000.00'));
    expect(csv, contains('Expense,₱1,250.00'));
    expect(csv, contains('Date,Type,Title,Category,Account,Amount,Note,Currency'));
    expect(csv, contains('2026-07-15,Expense,Jollibee,Food & Dining,Cash,1234.56,,PHP'));
  });

  test('CSV escapes quotes, commas and newlines in field values', () {
    final csv = ReportExporter.buildCsv(
      reportWith([
        TransactionContext(
          transaction: tx(
            id: 't2',
            type: TransactionType.expense,
            amountMinor: 500,
            merchant: 'Smith, "Big" & Sons',
            note: 'line one\nline two',
          ),
        ),
      ]),
    );

    expect(csv, contains('"Smith, ""Big"" & Sons"'));
    expect(csv, contains('"line one\nline two"'));
  });

  test('CSV handles income, refund and transfer rows', () {
    final csv = ReportExporter.buildCsv(
      reportWith([
        TransactionContext(
          transaction: tx(
            id: 'i1',
            type: TransactionType.income,
            amountMinor: 300000,
            merchant: 'Salary',
          ),
        ),
        TransactionContext(
          transaction: tx(
            id: 'r1',
            type: TransactionType.refund,
            amountMinor: 25000,
          ),
        ),
        TransactionContext(
          transaction: tx(
            id: 'x1',
            type: TransactionType.transfer,
            amountMinor: 10000,
          ),
        ),
      ]),
    );

    expect(csv, contains('Income,Salary'));
    expect(csv, contains('Refund'));
    expect(csv, contains('Transfer'));
  });

  test('PDF generation produces a valid PDF header', () async {
    final bytes = await ReportExporter.buildPdf(
      reportWith([
        TransactionContext(
          transaction: tx(
            id: 't3',
            type: TransactionType.expense,
            amountMinor: 99000,
            merchant: 'Electricity',
          ),
          accountName: 'Bank',
          categoryName: 'Utilities',
        ),
      ]),
    );

    expect(bytes, isNotEmpty);
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });

  test('PDF generation works with an empty month', () async {
    final bytes = await ReportExporter.buildPdf(reportWith(const []));
    expect(bytes, isNotEmpty);
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });
}
