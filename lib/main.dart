import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/demo_data_seeder.dart';
import 'app/router/app_router.dart';

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
