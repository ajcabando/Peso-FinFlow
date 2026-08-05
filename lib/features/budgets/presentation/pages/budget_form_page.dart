import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/app_providers.dart';
import '../../../../core/errors/app_exception.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/utils/money_input_parser.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../../accounts/domain/enums/account_type.dart';
import '../../../accounts/domain/models/account.dart';
import '../../../accounts/presentation/providers/account_providers.dart';
import '../../../accounts/presentation/widgets/category_form_sheet.dart';
import '../../domain/models/budget.dart';
import '../providers/budget_providers.dart';

/// Creates (or, with [budgetId], edits) a monthly budget for an expense
/// category.
class BudgetFormPage extends ConsumerStatefulWidget {
  const BudgetFormPage({super.key, this.budgetId});

  /// When set, the form loads and edits this budget instead of creating.
  final String? budgetId;

  @override
  ConsumerState<BudgetFormPage> createState() => _BudgetFormPageState();
}

class _BudgetFormPageState extends ConsumerState<BudgetFormPage> {
  final _amountController = TextEditingController();

  String? _categoryId;
  String _currency = 'PHP';
  Budget? _existing;
  bool _loading = false;
  bool _saving = false;

  /// Categories created inline during this session, so the dropdown can
  /// select a brand-new category before the reactive list refreshes.
  final List<Account> _createdCategories = [];

  bool get _editing => widget.budgetId != null;

  @override
  void initState() {
    super.initState();
    _currency = ref.read(defaultCurrencyProvider);
    if (_editing) {
      _loading = true;
      _load();
    }
  }

  Future<void> _load() async {
    final budget = await ref
        .read(budgetRepositoryProvider)
        .getById(widget.budgetId!);
    if (!mounted) return;
    if (budget == null) {
      context.showSnack('Budget not found.');
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
      return;
    }
    setState(() {
      _existing = budget;
      _loading = false;
      _categoryId = budget.categoryId;
      _currency = budget.currencyCode;
      _amountController.text = MoneyInputParser.toInput(
        budget.amountMinor,
        decimals: CurrencyFormatter.decimalDigits(budget.currencyCode),
      );
    });
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  /// Creates a new expense category inline; the budget then targets it
  /// directly without reopening the dropdown.
  Future<void> _createNewCategory() async {
    final created = await showCategoryFormSheet(
      context,
      initialType: AccountType.expense,
    );
    if (created != null && mounted) {
      setState(() {
        _createdCategories.add(created);
        _categoryId = created.id;
      });
    }
  }

  Future<void> _save() async {
    if (_categoryId == null) {
      context.showSnack('Select a category.');
      return;
    }
    final decimals = CurrencyFormatter.decimalDigits(_currency);
    final amountMinor = MoneyInputParser.parseMinor(
      _amountController.text,
      decimals: decimals,
    );
    if (amountMinor == null || amountMinor <= 0) {
      context.showSnack('Enter a valid monthly amount greater than zero.');
      return;
    }

    setState(() => _saving = true);
    try {
      await ref
          .read(budgetRepositoryProvider)
          .upsert(
            categoryId: _categoryId!,
            amountMinor: amountMinor,
            currencyCode: _currency,
          );
      if (!mounted) return;
      context.showSnack(_editing ? 'Budget updated' : 'Budget created');
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
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
        title: const Text('Delete budget?'),
        content: const Text(
          'This removes the monthly limit for this category. Nothing is '
          'changed in your ledger.',
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
      await ref.read(budgetRepositoryProvider).deleteBudget(widget.budgetId!);
      if (!mounted) return;
      context.showSnack('Budget deleted');
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
    } on FinFlowException catch (error) {
      if (!mounted) return;
      context.showSnack(error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final categories = ref.watch(categoriesProvider).value ?? const [];
    final budgets = ref.watch(budgetsProvider).value ?? const [];
    final budgetedIds = {for (final b in budgets) b.categoryId};

    final expenseCategories = categories
        .where((c) => c.type == AccountType.expense)
        .toList();
    // Inline-created categories are always offered so the dropdown can select
    // them before the reactive list refreshes (deduplicated against it).
    final withCreated = [
      ...expenseCategories,
      for (final created in _createdCategories)
        if (!expenseCategories.any((c) => c.id == created.id)) created,
    ];
    // When creating, hide categories that already have a budget; the edited
    // category stays visible so its limit can be changed.
    final options = _existing == null
        ? withCreated
              .where((c) => !budgetedIds.contains(c.id))
              .toList()
        : withCreated;

    return Scaffold(
      appBar: AppBar(title: Text(_editing ? 'Edit Budget' : 'New Budget')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        key: ValueKey('category-${_categoryId ?? 'none'}'),
                        initialValue: _categoryId,
                        decoration: const InputDecoration(
                          labelText: 'Expense category',
                          prefixIcon: Icon(Icons.category_outlined, size: 20),
                        ),
                        items: [
                          for (final category in options)
                            DropdownMenuItem(
                              value: category.id,
                              child: Text(category.name),
                            ),
                        ],
                        onChanged: (id) => setState(() {
                          _categoryId = id;
                          for (final category in categories) {
                            if (category.id == id) {
                              _currency = category.currencyCode;
                              break;
                            }
                          }
                          if (_editing) {
                            _amountController.text = MoneyInputParser.toInput(
                              _existing!.amountMinor,
                              decimals: CurrencyFormatter.decimalDigits(
                                _currency,
                              ),
                            );
                          }
                        }),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: TextButton.icon(
                        onPressed: _createNewCategory,
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('New'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                AppTextField(
                  label: 'Monthly limit',
                  hintText: '0.00',
                  prefixIcon: Icons.payments_outlined,
                  controller: _amountController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: Text(
                    'In $_currency '
                    '(${CurrencyFormatter.symbolFor(_currency).trim()}) — '
                    'spending is tracked automatically from your ledger.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                AppButton(
                  label: _editing ? 'Save Changes' : 'Create Budget',
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
                    label: const Text('Delete Budget'),
                  ),
                ],
                const SizedBox(height: AppSpacing.xl),
              ],
            ),
    );
  }
}
