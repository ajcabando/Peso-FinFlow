import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/app_providers.dart';
import '../../../../core/errors/app_exception.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radii.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_color_picker.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../domain/enums/account_kind.dart';
import '../../domain/enums/account_type.dart';
import '../../domain/models/account.dart';
import '../../domain/repositories/account_repository.dart';
import 'account_type_ui.dart';

/// Opens the category form as a modal bottom sheet.
///
/// With no [existing], creates a new category; the colour pre-selects the
/// next free palette colour among existing categories so every new category
/// is visually distinct. With [existing], edits (and can delete) it.
///
/// Returns the created/updated [Account], or `null` when dismissed.
Future<Account?> showCategoryFormSheet(
  BuildContext context, {
  AccountType? initialType,
  Account? existing,
}) {
  return showModalBottomSheet<Account>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.xl)),
    ),
    builder: (context) => _CategoryFormSheet(
      initialType: initialType,
      existing: existing,
    ),
  );
}

class _CategoryFormSheet extends ConsumerStatefulWidget {
  const _CategoryFormSheet({this.initialType, this.existing});

  final AccountType? initialType;
  final Account? existing;

  @override
  ConsumerState<_CategoryFormSheet> createState() =>
      _CategoryFormSheetState();
}

class _CategoryFormSheetState extends ConsumerState<_CategoryFormSheet> {
  final _nameController = TextEditingController();

  late AccountType _type;
  late int _color;
  String? _iconCode;
  bool _saving = false;

  bool get _editing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _type = existing.type;
      _color = existing.colorValue;
      _iconCode = existing.iconCode;
      _nameController.text = existing.name;
    } else {
      _type = widget.initialType ?? AccountType.expense;
      // Pre-select the next free palette colour among existing categories so
      // new categories stay visually distinct instead of defaulting to the
      // same static colour.
      _color = AppColors.accountPalette.first.toARGB32();
      ref
          .read(accountRepositoryProvider)
          .fetchCategories()
          .then((existingCategories) {
            if (!mounted) return;
            setState(
              () => _color = Account.dynamicColorValue(existingCategories),
            );
          });
      _iconCode = _type == AccountType.income ? 'payments' : 'restaurant';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      context.showSnack('Category name is required.');
      return;
    }

    setState(() => _saving = true);
    try {
      final repository = ref.read(accountRepositoryProvider);
      final Account saved;
      if (_editing) {
        final current = widget.existing!;
        saved = await repository.updateAccount(
          Account(
            id: current.id,
            name: name,
            kind: AccountKind.category,
            type: _type,
            status: current.status,
            openingBalanceMinor: 0,
            currencyCode: current.currencyCode,
            colorValue: _color,
            isHidden: current.isHidden,
            sortOrder: current.sortOrder,
            createdAt: current.createdAt,
            updatedAt: current.updatedAt,
            iconCode: _iconCode,
          ),
        );
      } else {
        saved = await repository.createAccount(
          CreateAccountInput(
            name: name,
            type: _type,
            kind: AccountKind.category,
            currencyCode: ref.read(defaultCurrencyProvider),
            colorValue: _color,
            iconCode: _iconCode,
          ),
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(saved);
    } on FinFlowException catch (error) {
      if (!mounted) return;
      context.showSnack(error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete category?'),
        content: const Text(
          'Categories that already appear on transactions cannot be '
          'deleted. If this category is unused, it will be removed '
          'permanently.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(accountRepositoryProvider).deleteAccount(
        widget.existing!.id,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } on FinFlowException catch (error) {
      if (!mounted) return;
      context.showSnack(error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;

    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.lg,
        right: AppSpacing.lg,
        top: AppSpacing.lg,
        bottom: MediaQuery.viewInsetsOf(context).bottom + AppSpacing.xl,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              _editing ? 'Edit Category' : 'New Category',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            AppTextField(
              label: 'Category name',
              hintText: _type == AccountType.income
                  ? 'e.g. Freelance'
                  : 'e.g. Groceries',
              prefixIcon: Icons.category_outlined,
              controller: _nameController,
              autofocus: !_editing,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _save(),
            ),
            if (!_editing) ...[
              const SizedBox(height: AppSpacing.lg),
              Text('Kind', style: theme.textTheme.titleSmall),
              const SizedBox(height: AppSpacing.sm),
              SegmentedButton<AccountType>(
                segments: const [
                  ButtonSegment(
                    value: AccountType.expense,
                    icon: Icon(Icons.trending_down_rounded),
                    label: Text('Expense'),
                  ),
                  ButtonSegment(
                    value: AccountType.income,
                    icon: Icon(Icons.trending_up_rounded),
                    label: Text('Income'),
                  ),
                ],
                selected: {_type},
                onSelectionChanged: (selection) => setState(() {
                  _type = selection.first;
                  if (_iconCode != 'payments' && _iconCode != 'restaurant') {
                    _iconCode = _type == AccountType.income
                        ? 'payments'
                        : 'restaurant';
                  }
                }),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            Text('Icon', style: theme.textTheme.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            _IconPicker(
              selected: _iconCode,
              onSelected: (code) => setState(() => _iconCode = code),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('Colour', style: theme.textTheme.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            AppColorPicker(
              selected: _color,
              onSelected: (color) => setState(() => _color = color),
            ),
            const SizedBox(height: AppSpacing.xl),
            AppButton(
              label: _editing ? 'Save Changes' : 'Create Category',
              icon: Icons.check,
              loading: _saving,
              onPressed: _save,
            ),
            if (_editing) ...[
              const SizedBox(height: AppSpacing.lg),
              FilledButton.tonalIcon(
                style: FilledButton.styleFrom(
                  backgroundColor: theme.colorScheme.errorContainer,
                  foregroundColor: theme.colorScheme.onErrorContainer,
                ),
                onPressed: _delete,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Delete Category'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A wrap of selectable category icons (stored as icon codes).
class _IconPicker extends StatelessWidget {
  const _IconPicker({required this.selected, required this.onSelected});

  final String? selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final code in categoryIconCodes)
          InkWell(
            onTap: () => onSelected(code),
            borderRadius: BorderRadius.circular(12),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: selected == code
                    ? scheme.primary.withValues(alpha: 0.14)
                    : scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: selected == code
                      ? scheme.primary
                      : scheme.outlineVariant,
                  width: selected == code ? 1.6 : 1,
                ),
              ),
              child: Icon(
                iconFromCode(code, fallback: Icons.category_outlined),
                size: 22,
                color: selected == code
                    ? scheme.primary
                    : scheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}
