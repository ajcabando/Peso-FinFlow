import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/accounts/domain/enums/account_type.dart';
import '../features/accounts/domain/repositories/account_repository.dart';
import '../features/transactions/domain/engine/transaction_builder.dart';
import 'providers/app_providers.dart';

/// Seeds realistic demo data (accounts, transactions, budgets, bills) so
/// store screenshots and preview builds look like a real, lived-in finance
/// app instead of an empty first run.
///
/// Only invoked when the app is built with
/// `--dart-define=FINFLOW_DEMO_DATA=true` (see main.dart). It is idempotent:
/// if any real accounts already exist it does nothing, so relaunching never
/// duplicates data.
Future<void> seedDemoData(ProviderContainer container) async {
  final accountRepository = container.read(accountRepositoryProvider);
  final existing = await accountRepository.fetchRealAccounts();
  if (existing.isNotEmpty) return;

  final transactionRepository = container.read(transactionRepositoryProvider);
  final budgetRepository = container.read(budgetRepositoryProvider);
  final billRepository = container.read(billRepositoryProvider);

  const currency = 'PHP';

  // ---- Real accounts (opening balances become ledger entries) ----
  final bdo = await accountRepository.createAccount(
    const CreateAccountInput(
      name: 'BDO Savings',
      type: AccountType.bank,
      institution: 'BDO',
      currencyCode: currency,
      openingBalanceMinor: 2500000, // ₱25,000
      iconCode: 'account_balance',
    ),
  );
  final gcash = await accountRepository.createAccount(
    const CreateAccountInput(
      name: 'GCash',
      type: AccountType.ewallet,
      institution: 'GCash',
      currencyCode: currency,
      openingBalanceMinor: 300000, // ₱3,000
      iconCode: 'account_balance_wallet',
    ),
  );
  final cash = await accountRepository.createAccount(
    const CreateAccountInput(
      name: 'Cash Wallet',
      type: AccountType.cash,
      currencyCode: currency,
      openingBalanceMinor: 150000, // ₱1,500
      iconCode: 'payments',
    ),
  );
  final maya = await accountRepository.createAccount(
    const CreateAccountInput(
      name: 'Maya',
      type: AccountType.ewallet,
      institution: 'Maya',
      currencyCode: currency,
      openingBalanceMinor: 500000, // ₱5,000
      iconCode: 'account_balance_wallet',
    ),
  );
  final bpiCard = await accountRepository.createAccount(
    const CreateAccountInput(
      name: 'BPI Credit',
      type: AccountType.creditCard,
      institution: 'BPI',
      currencyCode: currency,
      iconCode: 'credit_card',
    ),
  );

  // ---- Categories (seeded by DatabaseSeeder on first open) ----
  final categories = await accountRepository.fetchCategories();
  String categoryId(String name) =>
      categories.firstWhere((category) => category.name == name).id;
  final salary = categoryId('Salary');
  final food = categoryId('Food & Dining');
  final transport = categoryId('Transportation');
  final fuel = categoryId('Fuel');
  final utilities = categoryId('Utilities');
  final internet = categoryId('Internet');
  final subscriptions = categoryId('Subscriptions');
  final shopping = categoryId('Shopping');
  final entertainment = categoryId('Entertainment');
  final healthcare = categoryId('Healthcare');

  // ---- History depth: this month + 4 previous months ----
  final now = DateTime.now();
  final months = 5;

  // Salary lands on the 1st of every month.
  for (var m = months - 1; m >= 0; m--) {
    await transactionRepository.create(
      TransactionBuilder.income(
        occurredAt: DateTime(now.year, now.month - m, 1, 9),
        currencyCode: currency,
        toAccountId: bdo.id,
        categoryId: salary,
        amountMinor: 6500000, // ₱65,000
        merchant: 'Acme Corporation',
        note: 'Monthly salary',
      ),
    );
  }

  // Recurring everyday expenses. Days beyond "today" are skipped for the
  // current month so nothing is ever future-dated in the feed.
  final recurring = [
    (food, 'Jollibee', 24500, 2),
    (food, 'GrabFood', 32000, 4),
    (food, 'Starbucks', 18500, 6),
    (food, 'Chowking', 26000, 11),
    (transport, 'Grab Ride', 18500, 5),
    (transport, 'Angkas', 9500, 9),
    (fuel, 'Petron', 150000, 8),
    (utilities, 'Meralco', 350000, 14),
    (utilities, 'Maynilad', 85000, 16),
    (internet, 'PLDT Home', 169900, 10),
    (subscriptions, 'Netflix', 54900, 3),
    (subscriptions, 'Spotify', 14900, 7),
    (shopping, 'Shopee', 125000, 12),
    (shopping, 'Lazada', 98000, 18),
    (entertainment, 'SM Cinema', 80000, 13),
    (healthcare, 'Mercury Drug', 52000, 15),
  ];
  for (var m = months - 1; m >= 0; m--) {
    final maxDay = m == 0 ? now.day : 28;
    for (final (category, merchant, amount, day) in recurring) {
      if (day > maxDay) continue;
      await transactionRepository.create(
        TransactionBuilder.expense(
          occurredAt: DateTime(now.year, now.month - m, day, 18),
          currencyCode: currency,
          fromAccountId: day.isEven ? gcash.id : bdo.id,
          categoryId: category,
          amountMinor: amount,
          merchant: merchant,
        ),
      );
    }
  }

  // Credit card purchases + the monthly payment that settles them.
  for (var m = months - 1; m >= 0; m--) {
    final maxDay = m == 0 ? now.day : 28;
    if (12 <= maxDay) {
      await transactionRepository.create(
        TransactionBuilder.creditCardPurchase(
          occurredAt: DateTime(now.year, now.month - m, 12, 12),
          currencyCode: currency,
          creditCardAccountId: bpiCard.id,
          categoryId: shopping,
          amountMinor: 345000, // ₱3,450
          merchant: 'SM Department Store',
        ),
      );
    }
    if (20 <= maxDay) {
      await transactionRepository.create(
        TransactionBuilder.creditCardPayment(
          occurredAt: DateTime(now.year, now.month - m, 20, 10),
          currencyCode: currency,
          bankAccountId: bdo.id,
          creditCardAccountId: bpiCard.id,
          amountMinor: 345000,
          note: 'BPI Credit payment',
        ),
      );
    }
  }

  // A couple of wallet top-ups for the current month.
  if (2 <= now.day) {
    await transactionRepository.create(
      TransactionBuilder.transfer(
        occurredAt: DateTime(now.year, now.month, 2, 8),
        currencyCode: currency,
        fromAccountId: gcash.id,
        toAccountId: bdo.id,
        amountMinor: 500000, // ₱5,000
        note: 'GCash to BDO',
      ),
    );
  }
  if (3 <= now.day) {
    await transactionRepository.create(
      TransactionBuilder.transfer(
        occurredAt: DateTime(now.year, now.month, 3, 8),
        currencyCode: currency,
        fromAccountId: maya.id,
        toAccountId: gcash.id,
        amountMinor: 100000, // ₱1,000
        note: 'Maya to GCash',
      ),
    );
  }
  if (4 <= now.day) {
    await transactionRepository.create(
      TransactionBuilder.transfer(
        occurredAt: DateTime(now.year, now.month, 4, 8),
        currencyCode: currency,
        fromAccountId: cash.id,
        toAccountId: gcash.id,
        amountMinor: 200000, // ₱2,000
        note: 'Cash to GCash',
      ),
    );
  }

  // ---- Budgets for the current month ----
  await budgetRepository.upsert(
    categoryId: food,
    amountMinor: 600000, // ₱6,000
    currencyCode: currency,
  );
  await budgetRepository.upsert(
    categoryId: transport,
    amountMinor: 100000, // ₱1,000
    currencyCode: currency,
  );
  await budgetRepository.upsert(
    categoryId: entertainment,
    amountMinor: 120000, // ₱1,200
    currencyCode: currency,
  );

  // ---- Bills ----
  await billRepository.create(
    name: 'Meralco Electricity',
    amountMinor: 350000, // ₱3,500
    currencyCode: currency,
    accountId: bdo.id,
    dueDayOfMonth: 9,
    reminderDaysBefore: 5,
  );
  await billRepository.create(
    name: 'PLDT Home Fiber',
    amountMinor: 169900, // ₱1,699
    currencyCode: currency,
    accountId: bdo.id,
    dueDayOfMonth: 5,
    reminderDaysBefore: 2,
  );
  await billRepository.create(
    name: 'Netflix',
    amountMinor: 54900, // ₱549
    currencyCode: currency,
    accountId: bpiCard.id,
    dueDayOfMonth: 15,
    reminderDaysBefore: 3,
  );
}
