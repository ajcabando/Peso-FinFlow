import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/extensions/context_extensions.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_shadows.dart';
import 'quick_actions_sheet.dart';

/// The app-wide bottom navigation shell: a floating rounded pill with the
/// five main sections and a center FAB that opens the quick actions sheet.
class AppNavigationShell extends StatelessWidget {
  const AppNavigationShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    final heroGradient =
        Theme.of(context).extension<FinFlowTheme>()?.heroGradient ??
        const [AppColors.brandBright, AppColors.brand];

    // Settings (index 4) is where you manage the app, not where you add
    // transactions/accounts — hide the quick-actions FAB there so it never
    // floats over the profile card or About section.
    final showFab = shell.currentIndex != 4;

    return Scaffold(
      body: shell,
      floatingActionButton: showFab
          ? SizedBox(
              width: 60,
              height: 60,
              child: FloatingActionButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  showDragHandle: true,
                  builder: (_) => const QuickActionsSheet(),
                ),
                tooltip: 'Quick actions',
                backgroundColor: Colors.transparent,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadii.lg),
                ),
                child: Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: heroGradient,
                    ),
                    borderRadius: BorderRadius.circular(AppRadii.lg),
                    boxShadow: [
                      BoxShadow(
                        color: heroGradient.last.withValues(alpha: 0.45),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.add_rounded,
                    color: Colors.white,
                    size: 30,
                  ),
                ),
              ),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      bottomNavigationBar: _FloatingNavBar(shell: shell),
    );
  }
}

/// The floating pill: five destinations with a gradient pill for the active
/// one. The pill is elevated above the content with a hairline border.
class _FloatingNavBar extends StatelessWidget {
  const _FloatingNavBar({required this.shell});

  final StatefulNavigationShell shell;

  static const _destinations = [
    (icon: Icons.home_outlined, activeIcon: Icons.home_rounded, label: 'Home'),
    (
      icon: Icons.receipt_long_outlined,
      activeIcon: Icons.receipt_long_rounded,
      label: 'Transactions',
    ),
    (
      icon: Icons.account_balance_wallet_outlined,
      activeIcon: Icons.account_balance_wallet,
      label: 'Accounts',
    ),
    (
      icon: Icons.pie_chart_outline,
      activeIcon: Icons.pie_chart_rounded,
      label: 'Analytics',
    ),
    (
      icon: Icons.settings_outlined,
      activeIcon: Icons.settings_rounded,
      label: 'Settings',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;
    final heroGradient =
        Theme.of(context).extension<FinFlowTheme>()?.heroGradient ??
        const [AppColors.brandBright, AppColors.brand];

    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(20, 0, 20, 14),
      child: Container(
        height: 66,
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDarkElevated : Colors.white,
          borderRadius: BorderRadius.circular(33),
          border: Border.all(
            color: isDark ? AppColors.borderDark : AppColors.borderLight,
          ),
          boxShadow: AppShadows.floating,
        ),
        child: Row(
          children: [
            for (var i = 0; i < _destinations.length; i++)
              Expanded(
                child: _NavItem(
                  icon: _destinations[i].icon,
                  activeIcon: _destinations[i].activeIcon,
                  label: _destinations[i].label,
                  selected: shell.currentIndex == i,
                  gradient: heroGradient,
                  onTap: () => shell.goBranch(
                    i,
                    initialLocation: i == shell.currentIndex,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.gradient,
    required this.onTap,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final List<Color> gradient;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;
    final muted = isDark
        ? AppColors.textOnDarkSecondary
        : AppColors.textSecondary;

    return Semantics(
      selected: selected,
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(27),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(27),
            gradient: selected
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: gradient,
                  )
                : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: Icon(
                  selected ? activeIcon : icon,
                  key: ValueKey(selected),
                  size: 22,
                  color: selected ? Colors.white : muted,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected ? Colors.white : muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
