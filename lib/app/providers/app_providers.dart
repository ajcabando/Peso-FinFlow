import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_palette.dart';
import '../../database/app_database.dart';
import '../../database/database_connection.dart';
import '../../features/accounts/data/repositories/account_repository_impl.dart';
import '../../features/accounts/domain/repositories/account_repository.dart';
import '../../features/bills/data/repositories/bill_repository_impl.dart';
import '../../features/bills/domain/repositories/bill_repository.dart';
import '../../features/budgets/data/repositories/budget_repository_impl.dart';
import '../../features/budgets/domain/repositories/budget_repository.dart';
import '../../features/transactions/data/repositories/transaction_repository_impl.dart';
import '../../features/transactions/domain/repositories/transaction_repository.dart';

/// Keys used in the `app_settings` table.
abstract final class SettingsKeys {
  static const String themeMode = 'settings.themeMode';
  static const String currency = 'settings.currency';
  static const String palette = 'settings.palette';

  // Security (Phase 11): salted PIN hash + preferences.
  static const String securityPin = 'security.pinHash';
  static const String securityBiometrics = 'security.biometrics';
  static const String securityAutoLock = 'security.autoLock';
}

/// The single application-wide database instance.
///
/// Override this provider in tests with an in-memory database.
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase(openDatabaseConnection());
  ref.onDispose(db.close);
  return db;
});

final transactionRepositoryProvider = Provider<TransactionRepository>(
  (ref) => TransactionRepositoryImpl(db: ref.watch(databaseProvider)),
);

final accountRepositoryProvider = Provider<AccountRepository>(
  (ref) => AccountRepositoryImpl(
    db: ref.watch(databaseProvider),
    transactionRepository: ref.watch(transactionRepositoryProvider),
  ),
);

final budgetRepositoryProvider = Provider<BudgetRepository>(
  (ref) => BudgetRepositoryImpl(db: ref.watch(databaseProvider)),
);

final billRepositoryProvider = Provider<BillRepository>(
  (ref) => BillRepositoryImpl(db: ref.watch(databaseProvider)),
);

final settingsDaoProvider = Provider(
  (ref) => ref.watch(databaseProvider).settingsDao,
);

/// User-selected theme mode, persisted in the local database.
final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);

class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    final dao = ref.watch(settingsDaoProvider);
    dao.get(SettingsKeys.themeMode).then((value) {
      if (value != null) {
        state = ThemeMode.values.byName(value);
      }
    });
    return ThemeMode.system;
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = mode;
    await ref.read(settingsDaoProvider).set(SettingsKeys.themeMode, mode.name);
  }
}

/// User-selected colour palette, persisted in the local database.
final themePaletteProvider = NotifierProvider<ThemePaletteNotifier, AppPalette>(
  ThemePaletteNotifier.new,
);

class ThemePaletteNotifier extends Notifier<AppPalette> {
  @override
  AppPalette build() {
    final dao = ref.watch(settingsDaoProvider);
    dao.get(SettingsKeys.palette).then((value) {
      if (value != null && value.isNotEmpty) state = AppPalettes.byId(value);
    });
    return AppPalettes.purple;
  }

  Future<void> setPalette(AppPalette palette) async {
    state = palette;
    await ref.read(settingsDaoProvider).set(SettingsKeys.palette, palette.id);
  }
}

/// Default currency for new accounts and dashboard formatting.
final defaultCurrencyProvider = NotifierProvider<CurrencyNotifier, String>(
  CurrencyNotifier.new,
);

class CurrencyNotifier extends Notifier<String> {
  @override
  String build() {
    final dao = ref.watch(settingsDaoProvider);
    dao.get(SettingsKeys.currency).then((value) {
      if (value != null && value.isNotEmpty) state = value;
    });
    return AppConstants.defaultCurrencyCode;
  }

  Future<void> setCurrency(String code) async {
    state = code;
    await ref.read(settingsDaoProvider).set(SettingsKeys.currency, code);
  }
}
