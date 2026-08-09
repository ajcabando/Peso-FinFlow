import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/demo_data_seeder.dart';
import 'app/router/app_router.dart';
import 'features/sync/domain/sync_config.dart';
import 'features/sync/data/sync/device_registry.dart';

/// When true (built with `--dart-define=FINFLOW_DEMO_DATA=true`), the app
/// seeds realistic demo data on first launch — used for store screenshots
/// and preview builds. Normal builds keep this off.
const bool _demoData = bool.fromEnvironment('FINFLOW_DEMO_DATA');

/// Debug-only screenshot helper: when built with demo data, jump to this
/// screen shortly after launch so store screenshots can be captured without
/// manual navigation. Values: analytics | transactions | accounts | (empty).
const String _screenshotScreen = String.fromEnvironment('FINFLOW_SCREEN');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Cloud sync is opt-in: the self-hosted API URL is compiled in via
  // `--dart-define=FINFLOW_API_URL`. Without it the app runs fully local.
  final syncConfig = SyncConfig.fromEnvironment();
  if (syncConfig.enabled) {
    // Warm the device identity so first-login is snappy; nothing else to
    // initialise eagerly — the sync stack is wired through Riverpod.
    await DeviceRegistry.instance.deviceId();
  }

  if (_demoData) {
    final container = ProviderContainer();
    await seedDemoData(container);
    runApp(
      UncontrolledProviderScope(
        container: container,
        child: const FinFlowApp(),
      ),
    );
    if (_screenshotScreen.isNotEmpty) {
      Future<void>.delayed(const Duration(seconds: 3), () {
        appRouter.go('/$_screenshotScreen');
      });
    }
  } else {
    runApp(const ProviderScope(child: FinFlowApp()));
  }
}
