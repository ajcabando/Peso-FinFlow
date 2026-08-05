import 'package:drift/native.dart';
import 'package:finflow/database/app_database.dart';
import 'package:finflow/features/accounts/domain/enums/account_type.dart';
import 'package:finflow/features/accounts/domain/repositories/account_repository.dart';
import 'package:finflow/features/accounts/presentation/pages/accounts_page.dart';
import 'package:finflow/features/accounts/presentation/widgets/account_card.dart';
import 'package:finflow/features/accounts/presentation/widgets/account_gradient_card.dart';
import 'package:finflow/shared/widgets/sparkline.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_database.dart';
import '../helpers/widget_harness.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  testWidgets('shows the empty state when there are no accounts', (
    tester,
  ) async {
    await tester.pumpWidget(
      pumpApp(db, child: const AccountsPage(), accountsWithBalances: const []),
    );
    await tester.pumpAndSettle();

    expect(find.text('No accounts yet'), findsOneWidget);
    expect(find.text('Add Account'), findsWidgets);
  });

  testWidgets('lists accounts with their balances', (tester) async {
    final harness = TestHarness.attach(db);
    final cash = await harness.accounts.createAccount(
      const CreateAccountInput(
        name: 'GCash',
        type: AccountType.ewallet,
        currencyCode: 'PHP',
        openingBalanceMinor: 150000,
      ),
    );
    final bank = await harness.accounts.createAccount(
      const CreateAccountInput(
        name: 'BDO Savings',
        type: AccountType.bank,
        currencyCode: 'PHP',
      ),
    );

    await tester.pumpWidget(
      pumpApp(
        db,
        child: const AccountsPage(),
        accountsWithBalances: [
          AccountWithBalance(account: cash, balanceMinor: 150000),
          AccountWithBalance(account: bank, balanceMinor: 0),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('GCash'), findsOneWidget);
    expect(find.text('BDO Savings'), findsOneWidget);
    expect(find.textContaining('₱1,500.00'), findsWidgets);
    expect(find.text('2 accounts'), findsOneWidget);
  });

  testWidgets('renders account cards with type labels and sparklines', (
    tester,
  ) async {
    final harness = TestHarness.attach(db);
    final cash = await harness.accounts.createAccount(
      const CreateAccountInput(
        name: 'Wallet',
        type: AccountType.cash,
        currencyCode: 'PHP',
        openingBalanceMinor: 100000,
      ),
    );
    final card = await harness.accounts.createAccount(
      const CreateAccountInput(
        name: 'Visa',
        type: AccountType.creditCard,
        currencyCode: 'PHP',
      ),
    );

    await tester.pumpWidget(
      pumpApp(
        db,
        child: const AccountsPage(),
        accountsWithBalances: [
          AccountWithBalance(account: cash, balanceMinor: 100000),
          AccountWithBalance(account: card, balanceMinor: 0),
        ],
      ),
    );
    await tester.pumpAndSettle();

    // Type labels identify each card.
    expect(find.text('Cash'), findsOneWidget);
    expect(find.text('Credit Card'), findsOneWidget);
    // Every account card renders its six-month sparkline.
    expect(find.byType(Sparkline), findsNWidgets(2));
    // Cards are colourful gradient surfaces, one per account.
    expect(find.byType(AccountGradientCard), findsNWidgets(2));
  });

  testWidgets('keeps text intact on a narrow phone with huge balances', (
    tester,
  ) async {
    // Typical narrow phone: 360 logical px wide.
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final harness = TestHarness.attach(db);
    final account = await harness.accounts.createAccount(
      const CreateAccountInput(
        name: 'My Super Long Bank Account Name',
        type: AccountType.bank,
        currencyCode: 'PHP',
        openingBalanceMinor: 98765432100,
      ),
    );

    await tester.pumpWidget(
      pumpApp(
        db,
        child: const AccountsPage(),
        accountsWithBalances: [
          AccountWithBalance(account: account, balanceMinor: 98765432100),
        ],
      ),
    );
    await tester.pumpAndSettle();

    // No RenderFlex overflow or any other layout exception on the narrow
    // viewport, even with a nine-figure balance and a long account name.
    // No RenderFlex overflow or any other layout exception on the narrow
    // viewport, even with a nine-figure balance and a long account name.
    expect(tester.takeException(), isNull);
    expect(find.text('My Super Long Bank Account Name'), findsOneWidget);
    // The full amount is present on both the hero and the card, scaled
    // rather than clipped.
    expect(find.textContaining('987,654,321.00'), findsNWidgets(2));
  });

  testWidgets('reflows account cards into columns on wide displays', (
    tester,
  ) async {
    // Wide display: cards should sit side by side instead of stretching.
    tester.view.physicalSize = const Size(900, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final harness = TestHarness.attach(db);
    for (final name in ['Wallet', 'GCash', 'BDO']) {
      await harness.accounts.createAccount(
        CreateAccountInput(
          name: name,
          type: AccountType.cash,
          currencyCode: 'PHP',
        ),
      );
    }
    final all = await WidgetDb.realAccounts(db);
    final entries = [
      for (final account in all)
        AccountWithBalance(account: account, balanceMinor: 10000),
    ];

    await tester.pumpWidget(
      pumpApp(
        db,
        child: const AccountsPage(),
        accountsWithBalances: entries,
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // 900 - 32 padding - 12 spacing over two columns → 428 each.
    final cardWidth = tester.getSize(find.byType(AccountCard).first).width;
    expect(cardWidth, closeTo(428, 1));
    // The first two cards share a row (2 columns on a 900px display).
    final first = tester.getTopLeft(find.byType(AccountCard).at(0));
    final second = tester.getTopLeft(find.byType(AccountCard).at(1));
    expect(first.dy, closeTo(second.dy, 1));
    // The third card wraps onto the next row.
    final third = tester.getTopLeft(find.byType(AccountCard).at(2));
    expect(third.dy, greaterThan(first.dy + 100));
  });
}
