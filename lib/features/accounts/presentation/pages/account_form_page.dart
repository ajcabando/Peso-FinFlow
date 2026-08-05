import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/app_providers.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/errors/app_exception.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/utils/money_input_parser.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_chip.dart';
import '../../../../shared/widgets/app_color_picker.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../domain/enums/account_type.dart';
import '../../domain/models/account.dart';
import '../../domain/repositories/account_repository.dart';

/// Creates (or, with [accountId], edits) an account.
///
/// A non-zero opening balance is recorded as a balanced opening-balance
/// ledger transaction automatically at creation time; the opening balance
/// cannot be changed afterwards.
class AccountFormPage extends ConsumerStatefulWidget {
  const AccountFormPage({super.key, this.accountId});

  /// When set, the form loads and edits this account instead of creating.
  final String? accountId;

  @override
  ConsumerState<AccountFormPage> createState() => _AccountFormPageState();
}

class _AccountFormPageState extends ConsumerState<AccountFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _institutionController = TextEditingController();
  final _notesController = TextEditingController();
  final _openingController = TextEditingController();

  AccountType _selectedType = AccountType.cash;
  String _currency = 'PHP';
  int _selectedColor = AppColors.accountPalette.first.toARGB32();
  Account? _existing;
  bool _loading = false;
  bool _saving = false;

  bool get _editing => widget.accountId != null;

  @override
  void initState() {
    super.initState();
    _currency = ref.read(defaultCurrencyProvider);
    if (_editing) {
      // Start in the loading state before the first frame; the form body
      // only mounts once the account is loaded, so fields mount with the
      // stored values (no stale dropdowns, no empty-form flash).
      _loading = true;
      _load();
    } else {
      // New account: pre-select a distinct colour from the palette so each
      // account gets its own shade instead of the same default purple.
      ref.read(accountRepositoryProvider).fetchRealAccounts().then((existing) {
        if (!mounted) return;
        setState(() => _selectedColor = Account.dynamicColorValue(existing));
      });
    }
  }

  Future<void> _load() async {
    final account = await ref
        .read(accountRepositoryProvider)
        .getById(widget.accountId!);
    if (!mounted) return;
    if (account == null) {
      context.showSnack('Account not found.');
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
      return;
    }
    setState(() {
      _existing = account;
      _loading = false;
      _nameController.text = account.name;
      _institutionController.text = account.institution ?? '';
      _notesController.text = account.notes ?? '';
      _selectedType = account.type;
      _currency = account.currencyCode;
      _selectedColor = account.colorValue;
      _openingController.text = MoneyInputParser.toInput(
        account.openingBalanceMinor,
        decimals: CurrencyFormatter.decimalDigits(account.currencyCode),
      );
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _institutionController.dispose();
    _notesController.dispose();
    _openingController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final decimals = CurrencyFormatter.decimalDigits(_currency);
    final openingMinor =
        MoneyInputParser.parseMinor(
          _openingController.text,
          decimals: decimals,
        ) ??
        0;

    setState(() => _saving = true);
    try {
      if (_editing) {
        final current = _existing;
        if (current == null) {
          throw const NotFoundException('Account not found.');
        }
        await ref
            .read(accountRepositoryProvider)
            .updateAccount(
              Account(
                id: current.id,
                name: _nameController.text.trim(),
                kind: current.kind,
                type: _selectedType,
                status: current.status,
                openingBalanceMinor: current.openingBalanceMinor,
                currencyCode: _currency,
                colorValue: _selectedColor,
                isHidden: current.isHidden,
                sortOrder: current.sortOrder,
                createdAt: current.createdAt,
                updatedAt: current.updatedAt,
                institution: _institutionController.text.trim().isEmpty
                    ? null
                    : _institutionController.text.trim(),
                iconCode: current.iconCode,
                notes: _notesController.text.trim().isEmpty
                    ? null
                    : _notesController.text.trim(),
              ),
            );
        if (!mounted) return;
        context.showSnack('Account updated');
      } else {
        await ref
            .read(accountRepositoryProvider)
            .createAccount(
              CreateAccountInput(
                name: _nameController.text.trim(),
                type: _selectedType,
                institution: _institutionController.text.trim().isEmpty
                    ? null
                    : _institutionController.text.trim(),
                currencyCode: _currency,
                openingBalanceMinor: openingMinor,
                colorValue: _selectedColor,
                notes: _notesController.text.trim().isEmpty
                    ? null
                    : _notesController.text.trim(),
              ),
            );
        if (!mounted) return;
        context.showSnack('Account created');
      }
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

    return Scaffold(
      appBar: AppBar(title: Text(_editing ? 'Edit Account' : 'New Account')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: [
                  AppTextField(
                    label: 'Account name',
                    hintText: 'e.g. BDO Savings',
                    prefixIcon: Icons.edit_outlined,
                    controller: _nameController,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text('Type', style: theme.textTheme.titleSmall),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      for (final type in AccountType.creatableTypes)
                        AppSelectableChip(
                          label: type.label,
                          selected: _selectedType == type,
                          onSelected: (_) =>
                              setState(() => _selectedType = type),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  AppTextField(
                    label: 'Institution (optional)',
                    hintText: 'e.g. BDO, GCash, Maya',
                    prefixIcon: Icons.apartment_outlined,
                    controller: _institutionController,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Row(
                    children: [
                      Expanded(
                        child: _CurrencyDropdown(
                          value: _currency,
                          onChanged: (value) => setState(() {
                            _currency = value;
                            if (!_editing) _openingController.text = '';
                          }),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: AppTextField(
                          label: 'Opening balance',
                          hintText: '0.00',
                          prefixIcon: Icons.payments_outlined,
                          controller: _openingController,
                          enabled: !_editing,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_editing)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.sm),
                      child: Text(
                        'The opening balance is recorded in the ledger at '
                        'creation and cannot be changed.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  const SizedBox(height: AppSpacing.lg),
                  Text('Colour', style: theme.textTheme.titleSmall),
                  const SizedBox(height: AppSpacing.sm),
                  AppColorPicker(
                    selected: _selectedColor,
                    onSelected: (color) =>
                        setState(() => _selectedColor = color),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  AppTextField(
                    label: 'Notes (optional)',
                    prefixIcon: Icons.notes_outlined,
                    controller: _notesController,
                    maxLines: 2,
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  AppButton(
                    label: _editing ? 'Save Changes' : 'Save Account',
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

class _CurrencyDropdown extends StatelessWidget {
  const _CurrencyDropdown({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      decoration: const InputDecoration(labelText: 'Currency'),
      items: [
        for (final code in AppConstants.supportedCurrencies)
          DropdownMenuItem(
            value: code,
            child: Text('$code · ${CurrencyFormatter.symbolFor(code)}'),
          ),
      ],
      onChanged: (code) {
        if (code != null) onChanged(code);
      },
    );
  }
}


