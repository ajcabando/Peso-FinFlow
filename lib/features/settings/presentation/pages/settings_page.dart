import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/app_providers.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_radii.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/section_header.dart';
import '../../../accounts/domain/enums/account_type.dart';
import '../../../accounts/domain/models/account.dart';
import '../../../accounts/presentation/providers/account_providers.dart';
import '../../../accounts/presentation/widgets/account_type_ui.dart';
import '../../../accounts/presentation/widgets/category_form_sheet.dart';

/// Appearance, currency and about — the foundation settings.
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final palette = ref.watch(themePaletteProvider);
    final currency = ref.watch(defaultCurrencyProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          _ProfileHeader(),
          const SizedBox(height: AppSpacing.xl),
          const SectionHeader(title: 'Appearance'),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Colour theme', style: context.textTheme.titleSmall),
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: AppSpacing.md,
                  runSpacing: AppSpacing.md,
                  children: [
                    for (final option in AppPalettes.all)
                      _PaletteOption(
                        palette: option,
                        selected: option.id == palette.id,
                        onTap: () => ref
                            .read(themePaletteProvider.notifier)
                            .setPalette(option),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                Text('Brightness', style: context.textTheme.titleSmall),
                const SizedBox(height: AppSpacing.md),
                SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(
                      value: ThemeMode.system,
                      icon: Icon(Icons.brightness_auto_outlined),
                      label: Text('System'),
                    ),
                    ButtonSegment(
                      value: ThemeMode.light,
                      icon: Icon(Icons.light_mode_outlined),
                      label: Text('Light'),
                    ),
                    ButtonSegment(
                      value: ThemeMode.dark,
                      icon: Icon(Icons.dark_mode_outlined),
                      label: Text('Dark'),
                    ),
                  ],
                  selected: {themeMode},
                  onSelectionChanged: (selection) => ref
                      .read(themeModeProvider.notifier)
                      .setThemeMode(selection.first),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          const SectionHeader(title: 'Defaults'),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Default currency', style: context.textTheme.titleSmall),
                const SizedBox(height: AppSpacing.sm),
                DropdownButtonFormField<String>(
                  initialValue: currency,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.currency_exchange, size: 20),
                  ),
                  items: [
                    for (final code in AppConstants.supportedCurrencies)
                      DropdownMenuItem(
                        value: code,
                        child: Text(
                          '${CurrencyFormatter.symbolFor(code)} $code',
                        ),
                      ),
                  ],
                  onChanged: (code) {
                    if (code != null) {
                      ref
                          .read(defaultCurrencyProvider.notifier)
                          .setCurrency(code);
                    }
                  },
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'New accounts open in this currency.',
                  style: context.textTheme.bodySmall?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          const SectionHeader(title: 'Categories'),
          const _CategoriesCard(),
          const SizedBox(height: AppSpacing.xl),
          const SectionHeader(title: 'Privacy'),
          AppCard(
            child: Row(
              children: [
                Icon(
                  Icons.offline_bolt_outlined,
                  color: context.colors.primary,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Local-first by design',
                        style: context.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'All data stays in a private on-device database. '
                        'Nothing leaves your device unless you choose to '
                        'sync or export. Device-level encryption ships with '
                        'the Security phase.',
                        style: context.textTheme.bodySmall?.copyWith(
                          color: context.colors.onSurfaceVariant,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          const SectionHeader(title: 'About'),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppConstants.appName,
                  style: context.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  AppConstants.tagline,
                  style: context.textTheme.bodySmall?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Version 0.1.0 · ${CurrencyFormatter.decimalDigits(currency)} decimal '
                  'digits for $currency',
                  style: context.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xxl),
        ],
      ),
    );
  }
}

/// Income & expense category manager: list, add, edit and delete categories
/// (new ones pre-select a distinct colour automatically).
class _CategoriesCard extends ConsumerWidget {
  const _CategoriesCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoriesProvider).value ?? const [];
    final income = categories
        .where((c) => c.type == AccountType.income)
        .toList();
    final expense = categories
        .where((c) => c.type == AccountType.expense)
        .toList();

    Future<void> openSheet({Account? existing, AccountType? initialType}) async {
      await showCategoryFormSheet(
        context,
        existing: existing,
        initialType: initialType,
      );
    }

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CategoryGroup(
            title: 'Income',
            categories: income,
            onAdd: () => openSheet(initialType: AccountType.income),
            onTap: (category) => openSheet(existing: category),
          ),
          const Divider(height: AppSpacing.xl),
          _CategoryGroup(
            title: 'Expense',
            categories: expense,
            onAdd: () => openSheet(initialType: AccountType.expense),
            onTap: (category) => openSheet(existing: category),
          ),
        ],
      ),
    );
  }
}

/// A titled list of categories with an add button and tappable rows.
class _CategoryGroup extends StatelessWidget {
  const _CategoryGroup({
    required this.title,
    required this.categories,
    required this.onAdd,
    required this.onTap,
  });

  final String title;
  final List<Account> categories;
  final VoidCallback onAdd;
  final ValueChanged<Account> onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: context.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add'),
            ),
          ],
        ),
        if (categories.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Text(
              'No $title categories yet.',
              style: context.textTheme.bodySmall?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
          )
        else
          for (final category in categories)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: category.color,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  iconFromCode(
                    category.iconCode,
                    fallback: Icons.category_outlined,
                  ),
                  color: Colors.white,
                  size: 20,
                ),
              ),
              title: Text(
                category.name,
                style: context.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              trailing: Icon(
                Icons.chevron_right,
                color: context.colors.onSurfaceVariant,
              ),
              onTap: () => onTap(category),
            ),
      ],
    );
  }
}

/// Profile hero card shown at the top of Settings.
class _ProfileHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final heroGradient =
        Theme.of(context).extension<FinFlowTheme>()?.heroGradient ??
        const [AppColors.brandBright, AppColors.brand];

    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadii.xl),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: heroGradient,
        ),
        boxShadow: [
          BoxShadow(
            color: heroGradient.last.withValues(alpha: 0.35),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.person_outline,
              color: Colors.white,
              size: 30,
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppConstants.appName,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  AppConstants.tagline,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A single selectable palette swatch: gradient circle with label and a
/// check mark when active.
class _PaletteOption extends StatelessWidget {
  const _PaletteOption({
    required this.palette,
    required this.selected,
    required this.onTap,
  });

  final AppPalette palette;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: palette.heroGradient,
                ),
                border: Border.all(
                  color: selected ? scheme.primary : Colors.transparent,
                  width: 3,
                ),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: palette.heroGradient.last.withValues(
                            alpha: 0.4,
                          ),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ]
                    : null,
              ),
              child: selected
                  ? const Icon(Icons.check_rounded, color: Colors.white, size: 22)
                  : Icon(
                      palette.icon,
                      color: Colors.white.withValues(alpha: 0.85),
                      size: 20,
                    ),
            ),
            const SizedBox(height: 6),
            Text(
              palette.label,
              style: context.textTheme.labelSmall?.copyWith(
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? scheme.primary : scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
