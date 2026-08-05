import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/app_providers.dart';
import '../../domain/models/account.dart';
import '../../domain/repositories/account_repository.dart';

/// All accounts (including categories), reactive.
final accountsProvider = StreamProvider<List<Account>>(
  (ref) => ref.watch(accountRepositoryProvider).watchAccounts(),
);

/// Real financial accounts, reactive.
final realAccountsProvider = StreamProvider<List<Account>>(
  (ref) => ref.watch(accountRepositoryProvider).watchRealAccounts(),
);

/// Virtual income/expense categories, reactive.
final categoriesProvider = StreamProvider<List<Account>>(
  (ref) => ref.watch(accountRepositoryProvider).watchCategories(),
);

/// Real accounts with their derived balances, reactive.
final accountsWithBalancesProvider = StreamProvider<List<AccountWithBalance>>(
  (ref) => ref.watch(accountRepositoryProvider).watchAccountsWithBalances(),
);

/// Total Net Worth across visible real accounts, reactive.
final netWorthProvider = StreamProvider<int>(
  (ref) => ref.watch(accountRepositoryProvider).watchNetWorthMinor(),
);
