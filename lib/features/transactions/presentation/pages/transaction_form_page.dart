import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/app_providers.dart';
import '../../../../core/errors/app_exception.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_radii.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_chip.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../../accounts/domain/enums/account_type.dart';
import '../../../accounts/domain/models/account.dart';
import '../../../accounts/presentation/providers/account_providers.dart';
import '../../../accounts/presentation/widgets/category_form_sheet.dart';
import '../../../../core/utils/money_input_parser.dart';
import '../../domain/engine/transaction_builder.dart';
import '../../domain/enums/transaction_type.dart';
import '../providers/transaction_providers.dart';

/// Records (or edits) a transaction into the double-entry ledger.
///
/// The form adapts to the selected type: expenses pick a source account and
/// an expense category, income picks a destination account and an income
/// category, transfers pick two real accounts, and refunds return money to an
/// account under any category. Saving goes through [TransactionBuilder] and
/// the repository, which validate and persist the balanced entries atomically.
class TransactionFormPage extends ConsumerStatefulWidget {
  const TransactionFormPage({
    super.key,
    this.accountId,
    this.initialType,
    this.transactionId,
  });

  /// Pre-select this account (e.g. coming from an account detail page).
  final String? accountId;

  /// Pre-select this transaction type.
  final TransactionType? initialType;

  /// When set, the form loads and edits this existing transaction.
  final String? transactionId;

  @override
  ConsumerState<TransactionFormPage> createState() =>
      _TransactionFormPageState();
}

class _TransactionFormPageState extends ConsumerState<TransactionFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _merchantController = TextEditingController();
  final _noteController = TextEditingController();

  TransactionType _type = TransactionType.expense;
  DateTime _occurredAt = DateTime.now();
  String? _sourceAccountId;
  String? _destinationAccountId;
  String? _categoryId;
  String? _editCurrencyCode;
  bool _saving = false;
  bool _prefilled = false;

  /// Categories created inline during this session. Kept so the dropdown can
  /// show (and select) a brand-new category immediately, before the reactive
  /// category list refreshes — and deduplicated against it by id.
  final List<Account> _createdCategories = [];

  bool get _isEditing => widget.transactionId != null;

  @override
  void initState() {
    super.initState();
    if (widget.initialType != null) _type = widget.initialType!;
    _sourceAccountId = widget.accountId;

    if (_isEditing) {
      // Load the existing transaction and pre-fill every field once.
      ref.listenManual(transactionEditDataProvider(widget.transactionId!), (
        previous,
        next,
      ) {
        final data = next.value;
        if (data == null || _prefilled) return;
        _prefilled = true;
        _type = data.transaction.type;
        _occurredAt = data.transaction.occurredAt;
        _editCurrencyCode = data.transaction.currencyCode;
        _sourceAccountId = data.sourceAccountId;
        _destinationAccountId = data.destinationAccountId;
        _categoryId = data.categoryId;
        _amountController.text = MoneyInputParser.toInput(
          data.transaction.amountMinor,
          decimals: CurrencyFormatter.decimalDigits(
            data.transaction.currencyCode,
          ),
        );
        _merchantController.text = data.transaction.merchant ?? '';
        _noteController.text = data.transaction.note ?? '';
        if (mounted) setState(() {});
      });
    }

    // Adopt sensible selections once accounts are known. A manual listener
    // (rather than assignments inside build) keeps state side-effect free.
    ref.listenManual(realAccountsProvider, (previous, next) {
      final accounts = next.value;
      if (accounts == null || accounts.isEmpty) return;
      _sourceAccountId ??= accounts.first.id;
      if (_isTransfer && _destinationAccountId == null) {
        for (final account in accounts) {
          if (account.id != _sourceAccountId) {
            _destinationAccountId = account.id;
            break;
          }
        }
      }
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _amountController.dispose();
    _merchantController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  bool get _isTransfer => _type == TransactionType.transfer;

  bool get _needsCategory =>
      _type == TransactionType.expense ||
      _type == TransactionType.income ||
      _type == TransactionType.refund;

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _occurredAt,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        _occurredAt = DateTime(
          picked.year,
          picked.month,
          picked.day,
          _occurredAt.hour,
          _occurredAt.minute,
        );
      });
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_occurredAt),
    );
    if (picked != null) {
      setState(() {
        _occurredAt = DateTime(
          _occurredAt.year,
          _occurredAt.month,
          _occurredAt.day,
          picked.hour,
          picked.minute,
        );
      });
    }
  }

  String get _activeCurrency {
    if (_editCurrencyCode != null) return _editCurrencyCode!;
    final accounts = _realAccounts;
    final id = _sourceAccountId ?? _destinationAccountId;
    if (id != null) {
      final account = accounts.firstWhere(
        (a) => a.id == id,
        orElse: () => accounts.first,
      );
      return account.currencyCode;
    }
    return ref.read(defaultCurrencyProvider);
  }

  List<Account> get _realAccounts =>
      ref.watch(realAccountsProvider).value ?? const [];

  List<Account> get _categories =>
      ref.watch(categoriesProvider).value ?? const [];

  List<Account> get _categoryOptions {
    List<Account> matching(List<Account> list) => switch (_type) {
      TransactionType.income =>
        list.where((c) => c.type == AccountType.income).toList(),
      TransactionType.expense =>
        list.where((c) => c.type == AccountType.expense).toList(),
      _ => list,
    };

    final base = matching(_categories);
    final ids = {for (final category in base) category.id};
    return [
      ...base,
      for (final category in matching(_createdCategories))
        if (!ids.contains(category.id)) category,
    ];
  }

  /// Opens the category form; the new category is selected automatically so
  /// it can be used immediately without reopening the dropdown.
  Future<void> _createNewCategory() async {
    final created = await showCategoryFormSheet(
      context,
      initialType: _type == TransactionType.income
          ? AccountType.income
          : AccountType.expense,
    );
    if (created != null && mounted) {
      setState(() {
        _createdCategories.add(created);
        _categoryId = created.id;
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final decimals = CurrencyFormatter.decimalDigits(_activeCurrency);
    final amountMinor = MoneyInputParser.parseMinor(
      _amountController.text,
      decimals: decimals,
    );
    if (amountMinor == null || amountMinor <= 0) {
      context.showSnack('Enter a valid amount greater than zero.');
      return;
    }
    if (_sourceAccountId == null) {
      context.showSnack('Select an account.');
      return;
    }
    if (_isTransfer && _destinationAccountId == null) {
      context.showSnack('Select a destination account.');
      return;
    }
    if (_needsCategory && _categoryId == null) {
      context.showSnack('Select a category.');
      return;
    }

    setState(() => _saving = true);
    try {
      final draft = switch (_type) {
        TransactionType.expense => TransactionBuilder.expense(
          occurredAt: _occurredAt,
          currencyCode: _activeCurrency,
          fromAccountId: _sourceAccountId!,
          categoryId: _categoryId!,
          amountMinor: amountMinor,
          merchant: _merchantController.text.trim().isEmpty
              ? null
              : _merchantController.text.trim(),
          note: _noteController.text.trim().isEmpty
              ? null
              : _noteController.text.trim(),
        ),
        TransactionType.income => TransactionBuilder.income(
          occurredAt: _occurredAt,
          currencyCode: _activeCurrency,
          toAccountId: _sourceAccountId!,
          categoryId: _categoryId!,
          amountMinor: amountMinor,
          merchant: _merchantController.text.trim().isEmpty
              ? null
              : _merchantController.text.trim(),
          note: _noteController.text.trim().isEmpty
              ? null
              : _noteController.text.trim(),
        ),
        TransactionType.transfer => TransactionBuilder.transfer(
          occurredAt: _occurredAt,
          currencyCode: _activeCurrency,
          fromAccountId: _sourceAccountId!,
          toAccountId: _destinationAccountId!,
          amountMinor: amountMinor,
          note: _noteController.text.trim().isEmpty
              ? null
              : _noteController.text.trim(),
        ),
        TransactionType.refund => TransactionBuilder.refund(
          occurredAt: _occurredAt,
          currencyCode: _activeCurrency,
          toAccountId: _sourceAccountId!,
          categoryId: _categoryId!,
          amountMinor: amountMinor,
          note: _noteController.text.trim().isEmpty
              ? null
              : _noteController.text.trim(),
        ),
        TransactionType.adjustment ||
        TransactionType.openingBalance => throw const ValidationException(
          'This form only records daily '
          'activity; adjustments are applied by the system.',
        ),
      };

      if (_isEditing) {
        await ref
            .read(transactionRepositoryProvider)
            .update(widget.transactionId!, draft);
      } else {
        await ref.read(transactionRepositoryProvider).create(draft);
      }
      if (!mounted) return;
      context.showSnack(
        _isEditing ? 'Transaction updated' : '${_type.label} recorded',
      );
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
    } on FinFlowException catch (error) {
      if (!mounted) return;
      context.showSnack(error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final accounts = _realAccounts;
    final categoryOptions = _categoryOptions;

    if (_isEditing && !_prefilled) {
      // Wait for the existing transaction to load before showing the form.
      return Scaffold(
        appBar: AppBar(title: const Text('Edit Transaction')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final heroGradient =
        Theme.of(context).extension<FinFlowTheme>()?.heroGradient ??
        const [AppColors.brandBright, AppColors.brand];

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Transaction' : 'Add Transaction'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            // Large gradient amount hero.
            Container(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadii.xl),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: heroGradient,
                ),
              ),
              child: Theme(
                data: Theme.of(context).copyWith(
                  inputDecorationTheme: InputDecorationTheme(
                    labelStyle: TextStyle(
                      color: Colors.white.withValues(alpha: 0.75),
                      fontWeight: FontWeight.w600,
                    ),
                    hintStyle: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: AppTextField(
                        label: 'Amount',
                        hintText: '0.00',
                        controller: _amountController,
                        autofocus: true,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 38,
                          fontWeight: FontWeight.w700,
                          fontFamily: AppTypography.fontFamily,
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(12),
                      ),                        child: Text(
                          _activeCurrency,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontFamily: AppTypography.fontFamily,
                          ),
                        ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('Type', style: theme.textTheme.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final type in const [
                  TransactionType.expense,
                  TransactionType.income,
                  TransactionType.transfer,
                  TransactionType.refund,
                ])
                  AppSelectableChip(
                    label: type.label,
                    selected: _type == type,
                    onSelected: (_) => setState(() {
                      _type = type;
                      _categoryId = null;
                      _destinationAccountId = null;
                      // For transfers, pick a sensible counterpart right
                      // away so the form is ready to save.
                      if (type == TransactionType.transfer &&
                          _sourceAccountId != null) {
                        for (final account in _realAccounts) {
                          if (account.id != _sourceAccountId) {
                            _destinationAccountId = account.id;
                            break;
                          }
                        }
                      }
                    }),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: _DateTimeTile(
                    icon: Icons.event_outlined,
                    label: 'Date',
                    value: _occurredAt,
                    onTap: _pickDate,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: _DateTimeTile(
                    icon: Icons.schedule_outlined,
                    label: 'Time',
                    value: _occurredAt,
                    onTap: _pickTime,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            _AccountField(
              // Re-keyed by selection so the dropdown reflects state changes
              // (FormField initialValue is only honoured on first mount).
              key: ValueKey('source-${_sourceAccountId ?? 'none'}'),
              label: _isTransfer || _type == TransactionType.expense
                  ? 'From account'
                  : 'To account',
              value: _sourceAccountId,
              accounts: accounts,
              onChanged: (id) => setState(() {
                _sourceAccountId = id;
                if (_isTransfer && id == _destinationAccountId) {
                  _destinationAccountId = null;
                }
              }),
            ),
            if (_isTransfer) ...[
              const SizedBox(height: AppSpacing.lg),
              _AccountField(
                key: ValueKey('destination-${_destinationAccountId ?? 'none'}'),
                label: 'To account',
                value: _destinationAccountId,
                accounts: accounts
                    .where((a) => a.id != _sourceAccountId)
                    .toList(),
                onChanged: (id) => setState(() => _destinationAccountId = id),
              ),
            ],
            if (_needsCategory) ...[
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  Expanded(
                    child: Text('Category', style: theme.textTheme.titleSmall),
                  ),
                  TextButton.icon(
                    onPressed: _createNewCategory,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('New'),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              // Quick category buttons: tap a coloured circle to pre-select.
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final category in categoryOptions.take(8))
                    _QuickCategoryButton(
                      category: category,
                      selected: _categoryId == category.id,
                      onTap: () => setState(() => _categoryId = category.id),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              _CategoryField(
                key: ValueKey('category-${_type.name}'),
                label: _type == TransactionType.income
                    ? 'Income category'
                    : 'More…',
                value: _categoryId,
                categories: categoryOptions,
                onChanged: (id) => setState(() => _categoryId = id),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            AppTextField(
              label: 'Merchant (optional)',
              hintText: 'e.g. Jollibee, Netflix',
              prefixIcon: Icons.store_outlined,
              controller: _merchantController,
            ),
            const SizedBox(height: AppSpacing.lg),
            AppTextField(
              label: 'Note (optional)',
              prefixIcon: Icons.notes_outlined,
              controller: _noteController,
              maxLines: 2,
            ),
            const SizedBox(height: AppSpacing.xl),
            AppButton(
              label: 'Save Transaction',
              icon: Icons.check,
              loading: _saving,
              onPressed: _save,
            ),
            const SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
    );
  }
}

class _DateTimeTile extends StatelessWidget {
  const _DateTimeTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final DateTime value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, size: 20),
        ),
        child: Text(
          label == 'Time'
              ? '${value.hour.toString().padLeft(2, '0')}:'
                    '${value.minute.toString().padLeft(2, '0')}'
              : '${value.month}/${value.day}/${value.year}',
          style: theme.textTheme.bodyLarge,
        ),
      ),
    );
  }
}

class _AccountField extends StatelessWidget {
  const _AccountField({
    super.key,
    required this.label,
    required this.value,
    required this.accounts,
    required this.onChanged,
  });

  final String label;
  final String? value;
  final List<Account> accounts;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      decoration: InputDecoration(labelText: label),
      items: [
        for (final account in accounts)
          DropdownMenuItem(
            value: account.id,
            child: Text('${account.name} · ${account.currencyCode}'),
          ),
      ],
      onChanged: accounts.isEmpty
          ? null
          : (id) {
              if (id != null) onChanged(id);
            },
    );
  }
}

/// A coloured circular quick-category button; tapping pre-selects it.
class _QuickCategoryButton extends StatelessWidget {
  const _QuickCategoryButton({
    required this.category,
    required this.selected,
    required this.onTap,
  });

  final Account category;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = category.color;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: 0.18)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? color : scheme.outlineVariant,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
              child: selected
                  ? const Icon(
                      Icons.check_rounded,
                      size: 14,
                      color: Colors.white,
                    )
                  : null,
            ),
            const SizedBox(width: 8),
            Text(
              category.name,
              style: TextStyle(
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: selected ? color : scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryField extends StatelessWidget {
  const _CategoryField({
    super.key,
    required this.label,
    required this.value,
    required this.categories,
    required this.onChanged,
  });

  final String label;
  final String? value;
  final List<Account> categories;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      decoration: InputDecoration(labelText: label),
      items: [
        for (final category in categories)
          DropdownMenuItem(value: category.id, child: Text(category.name)),
      ],
      onChanged: categories.isEmpty
          ? null
          : (id) {
              if (id != null) onChanged(id);
            },
    );
  }
}
