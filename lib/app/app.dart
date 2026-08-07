import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import '../features/security/presentation/widgets/security_gate.dart';
import '../features/sync/presentation/widgets/sync_bootstrap.dart';
import 'providers/app_providers.dart';
import 'router/app_router.dart';

/// The root widget of the FinFlow application.
class FinFlowApp extends ConsumerWidget {
  const FinFlowApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final palette = ref.watch(themePaletteProvider);

    return SecurityGate(
      child: SyncBootstrap(
        child: MaterialApp.router(
        title: 'FinFlow',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(palette: palette),
        darkTheme: AppTheme.dark(palette: palette),
        themeMode: themeMode,
        routerConfig: appRouter,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en')],
        ),
      ),
    );
  }
}
