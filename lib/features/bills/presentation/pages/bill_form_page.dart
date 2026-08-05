import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/app_providers.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/errors/app_exception.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/utils/money_input_parser.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../../accounts/presentation/providers/account_providers.dart';

/// Creates (or, with [billId], edits) a recurring bill.
class BillFormPage extends ConsumerStatefulWidget {
  const BillFormPage({super.key, this.billId});

  /// When set, the form loads and edits this bill instead of creating.
  final String? billId;

  @override
  ConsumerState<BillFormPage> createState() => _BillFormPageState();
}

class _BillFormPageState extends ConsumerState<BillFormPage> {
  final _nameController = TextEditingController();
  final _amountController = TextEditingController();

  String _currency = 'PHP';
  String? _accountId;
  int _dueDay = 1;
  int _reminderDays = 3;
  bool _isActive = true;
  bool _loading = false;
  bool _saving = false;

  bool get _editing => widget.billId != null;

  @override
  void initState() {
    super.initState();
    _currency = ref.read(defaultCurrencyProvider);
    if (_editing) _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final bill = await ref.read(billRepositoryProvider).getById(widget.billId!);
    if (!mounted) return;
    if (bill == null) {
      context.showSnack('Bill not found.');
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
      return;
    }
    setState(() {
      _loading = false;
      _nameController.text = bill.name;
      _currency = bill.currencyCode;
      _accountId = bill.accountId;
      _dueDay = bill.dueDayOfMonth;
      _reminderDays = bill.reminderDaysBefore;
      _isActive = bill.isActive;
      _amountController.text = MoneyInputParser.toInput(
        bill.amountMinor,
        decimals: CurrencyFormatter.decimalDigits(bill.currencyCode),
      );
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final decimals = CurrencyFormatter.decimalDigits(_currency);
    final amountMinor = MoneyInputParser.parseMinor(
      _amountController.text,
      decimals: decimals,
    );
    if (_nameController.text.trim().isEmpty) {
      context.showSnack('Give the bill a name.');
      return;
    }
    if (amountMinor == null || amountMinor <= 0) {
      context.showSnack('Enter a valid amount greater than zero.');
      return;
    }

    setState(() => _saving = true);
    try {
      final repository = ref.read(billRepositoryProvider);
      if (_editing) {
        await repository.update(
          id: widget.billId!,
          name: _nameController.text,
          amountMinor: amountMinor,
          currencyCode: _currency,
          accountId: _accountId,
          dueDayOfMonth: _dueDay,
          reminderDaysBefore: _reminderDays,
          isActive: _isActive,
        );
      } else {
        await repository.create(
          name: _nameController.text,
          amountMinor: amountMinor,
          currencyCode: _currency,
          accountId: _accountId,
          dueDayOfMonth: _dueDay,
          reminderDaysBefore: _reminderDays,
        );
      }
      if (!mounted) return;
      context.showSnack(_editing ? 'Bill updated' : 'Bill added');
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
        title: const Text('Delete bill?'),
        content: const Text(
          'This removes the reminder. Nothing is changed in your ledger.',
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
      await ref.read(billRepositoryProvider).deleteBill(widget.billId!);
      if (!mounted) return;
      context.showSnack('Bill deleted');
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
    } on FinFlowException catch (error) {
      if (!mounted) return;
      context.showSnack(error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accounts = ref.watch(realAccountsProvider).value ?? const [];

    return Scaffold(
      appBar: AppBar(title: Text(_editing ? 'Edit Bill' : 'New Bill')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                AppTextField(
                  label: 'Bill name',
                  hintText: 'e.g. Internet, Netflix, Rent…',
                  prefixIcon: Icons.receipt_long_outlined,
                  controller: _nameController,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: AppSpacing.lg),
                AppTextField(
                  label: 'Amount',
                  hintText: '0.00',
                  prefixIcon: Icons.payments_outlined,
                  controller: _amountController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                DropdownButtonFormField<String>(
                  initialValue: _currency,
                  decoration: const InputDecoration(
                    labelText: 'Currency',
                    prefixIcon: Icon(Icons.currency_exchange, size: 20),
                  ),
                  items: [
                    for (final code in AppConstants.supportedCurrencies)
                      DropdownMenuItem(
                        value: code,
                        child: Text(
                          '${CurrencyFormatter.symbolFor(code).trim()} $code',
                        ),
                      ),
                  ],
                  onChanged: (code) {
                    if (code != null) setState(() => _currency = code);
                  },
                ),
                const SizedBox(height: AppSpacing.lg),
                DropdownButtonFormField<String?>(
                  initialValue: _accountId,
                  decoration: const InputDecoration(
                    labelText: 'Paid from (optional)',
                    prefixIcon: Icon(Icons.account_balance_wallet_outlined,
                        size: 20),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('No linked account'),
                    ),
                    for (final account in accounts)
                      DropdownMenuItem<String?>(
                        value: account.id,
                        child: Text(account.name),
                      ),
                  ],
                  onChanged: (id) => setState(() => _accountId = id),
                ),
                const SizedBox(height: AppSpacing.lg),
                DropdownButtonFormField<int>(
                  initialValue: _dueDay,
                  decoration: const InputDecoration(
                    labelText: 'Due day of month',
                    prefixIcon: Icon(Icons.event_outlined, size: 20),
                  ),
                  items: [
                    for (var day = 1; day <= 31; day++)
                      DropdownMenuItem(
                        value: day,
                        child: Text(
                          day == 1
                              ? '1st'
                              : day == 2
                              ? '2nd'
                              : day == 3
                              ? '3rd'
                              : '${day}th',
                        ),
                      ),
                  ],
                  onChanged: (day) {
                    if (day != null) setState(() => _dueDay = day);
                  },
                ),
                const SizedBox(height: AppSpacing.lg),
                DropdownButtonFormField<int>(
                  initialValue: _reminderDays,
                  decoration: const InputDecoration(
                    labelText: 'Remind me',
                    prefixIcon: Icon(Icons.notifications_active_outlined,
                        size: 20),
                  ),
                  items: const [
                    DropdownMenuItem(value: 0, child: Text('On the due day')),
                    DropdownMenuItem(value: 1, child: Text('1 day before')),
                    DropdownMenuItem(value: 2, child: Text('2 days before')),
                    DropdownMenuItem(value: 3, child: Text('3 days before')),
                    DropdownMenuItem(value: 5, child: Text('5 days before')),
                    DropdownMenuItem(value: 7, child: Text('A week before')),
                  ],
                  onChanged: (days) {
                    if (days != null) setState(() => _reminderDays = days);
                  },
                ),
                if (_editing) ...[
                  const SizedBox(height: AppSpacing.sm),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Bill is active'),
                    subtitle: const Text(
                      'Paused bills keep their history but stop reminding.',
                    ),
                    value: _isActive,
                    onChanged: (value) =>
                        setState(() => _isActive = value),
                  ),
                ],
                const SizedBox(height: AppSpacing.xl),
                AppButton(
                  label: _editing ? 'Save Changes' : 'Add Bill',
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
                    label: const Text('Delete Bill'),
                  ),
                ],
                const SizedBox(height: AppSpacing.xl),
              ],
            ),
    );
  }
}
