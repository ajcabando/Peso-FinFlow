import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/sync_session.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../accounts/presentation/providers/account_providers.dart';
import '../../../bills/presentation/providers/bill_providers.dart';
import '../../../budgets/presentation/providers/budget_providers.dart';
import '../../../transactions/presentation/providers/transaction_providers.dart';
import '../../domain/sync_status.dart';
import '../providers/sync_providers.dart';

/// Settings → Cloud backup card: passphrase setup, schedule picker,
/// "Back up now" and "Restore" (encrypted cloud snapshots).
class CloudBackupCard extends ConsumerStatefulWidget {
  const CloudBackupCard({super.key});

  @override
  ConsumerState<CloudBackupCard> createState() => _CloudBackupCardState();
}

class _CloudBackupCardState extends ConsumerState<CloudBackupCard> {
  final _passphrase = TextEditingController();
  bool _busy = false;
  bool _showPassphraseField = false;

  @override
  void dispose() {
    _passphrase.dispose();
    super.dispose();
  }

  bool get _signedIn => ref.watch(syncControllerProvider).signedIn;

  String? get _userId => SyncSession.instance.userId;

  Future<void> _backupNow() async {
    final passphrase = _passphrase.text.trim();
    if (passphrase.isEmpty) {
      setState(() => _showPassphraseField = true);
      if (mounted) context.showSnack('Enter a backup passphrase first.');
      return;
    }
    setState(() => _busy = true);
    try {
      // Goes through the controller so the passphrase is persisted and the
      // last-run time recorded (both required by the schedule trigger).
      final backup = await ref
          .read(syncControllerProvider.notifier)
          .backupNow(passphrase: passphrase);
      if (mounted) {
        context.showSnack('Cloud backup created — ${backup.sizeBytes} bytes');
      }
    } on Exception catch (e) {
      if (mounted) {
        context.showSnack(
          'Could not create the cloud backup: '
          '${e.toString().replaceFirst('Exception: ', '')}',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Stores the passphrase without creating a backup — enough to arm the
  /// daily/weekly/monthly schedule.
  Future<void> _savePassphrase() async {
    final passphrase = _passphrase.text.trim();
    if (passphrase.isEmpty) {
      if (mounted) context.showSnack('Enter a backup passphrase.');
      return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(syncControllerProvider.notifier)
          .saveBackupPassphrase(passphrase);
      if (mounted) context.showSnack('Backup passphrase saved');
    } on Exception catch (e) {
      if (mounted) {
        context.showSnack(e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setSchedule(BackupSchedule schedule) async {
    try {
      await ref
          .read(syncControllerProvider.notifier)
          .setBackupSchedule(schedule);
    } on Exception catch (e) {
      if (mounted) {
        context.showSnack(e.toString().replaceFirst('Exception: ', ''));
      }
    }
  }

  Future<void> _restore() async {
    final service = ref.read(cloudBackupServiceProvider);
    final userId = _userId;
    if (service == null || userId == null) return;
    if (!mounted) return;
    final passphrase = _passphrase.text.trim();
    if (passphrase.isEmpty) {
      setState(() => _showPassphraseField = true);
      if (mounted) context.showSnack('Enter your backup passphrase.');
      return;
    }
    final backups = await service.list();
    if (!mounted) return;
    if (backups.isEmpty) {
      if (mounted) context.showSnack('No cloud backups yet.');
      return;
    }
    final latest = backups.first;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Restore cloud backup?'),
        content: Text(
          'This replaces ALL data on this device with the cloud backup '
          'from ${_formatDate(latest.createdAt)}. This cannot be undone.',
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
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await service.restore(
        id: latest.id,
        passphrase: passphrase,
        userId: userId,
      );
      // A successful restore proves the passphrase — persist it so the
      // schedule can keep running unattended.
      await ref
          .read(syncControllerProvider.notifier)
          .saveBackupPassphrase(passphrase);
      _refreshProviders();
      if (mounted) context.showSnack('Cloud backup restored');
    } on Exception catch (e) {
      if (mounted) {
        context.showSnack(
          'Could not restore: ${e.toString().replaceFirst('Exception: ', '')}',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _refreshProviders() {
    ref.invalidate(accountsWithBalancesProvider);
    ref.invalidate(netWorthProvider);
    ref.invalidate(netWorthTrendProvider);
    ref.invalidate(monthlyCashFlowProvider);
    ref.invalidate(recentTransactionContextsProvider);
    ref.invalidate(allTransactionContextsProvider);
    ref.invalidate(allTransactionsProvider);
    ref.invalidate(categorySpendProvider);
    ref.invalidate(budgetProgressProvider);
    ref.invalidate(billsProvider);
    ref.invalidate(categoriesProvider);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final status = ref.watch(syncControllerProvider);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: colors.tertiary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  Icons.enhanced_encryption_outlined,
                  color: colors.tertiary,
                  size: 22,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Cloud backup (encrypted)',
                      style: context.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Your data is AES-256-GCM encrypted with your passphrase '
                      'before it ever leaves this device — the server never '
                      'sees it.',
                      style: textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_showPassphraseField) ...[
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _passphrase,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Backup passphrase',
                prefixIcon: Icon(Icons.key_outlined, size: 20),
                helperText: 'Used to encrypt and decrypt cloud backups. '
                    'Do not lose it — it cannot be recovered.',
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            AppButton(
              label: 'Save passphrase',
              icon: Icons.save_outlined,
              variant: AppButtonVariant.text,
              loading: _busy,
              onPressed: _savePassphrase,
            ),
          ] else if (!status.backupPassphraseSet) ...[
            const SizedBox(height: AppSpacing.sm),
            TextButton.icon(
              onPressed: () => setState(() => _showPassphraseField = true),
              icon: const Icon(Icons.key_outlined, size: 18),
              label: const Text('Set backup passphrase'),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          // Controlled dropdown: the displayed value always tracks the
          // provider state, so a failed (guarded) change reverts cleanly.
          InputDecorator(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.schedule_outlined, size: 20),
              labelText: 'Backup schedule',
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<BackupSchedule>(
                value: status.backupSchedule,
                isDense: true,
                isExpanded: true,
                items: [
                  for (final schedule in BackupSchedule.values)
                    DropdownMenuItem(
                      value: schedule,
                      child: Text(_scheduleLabel(schedule)),
                    ),
                ],
                onChanged: (schedule) {
                  if (schedule != null) _setSchedule(schedule);
                },
              ),
            ),
          ),
          if (status.backupPassphraseSet || status.lastBackupAt != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Icon(
                  status.backupPassphraseSet
                      ? Icons.check_circle_outline
                      : Icons.history,
                  size: 16,
                  color: colors.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    status.backupPassphraseSet
                        ? 'Passphrase saved on this device'
                        : '',
                    style: textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
                if (status.lastBackupAt != null)
                  Text(
                    'Last backup: ${_formatDateTime(status.lastBackupAt!)}',
                    style: textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  label: 'Back up now',
                  icon: Icons.cloud_upload_outlined,
                  variant: AppButtonVariant.secondary,
                  loading: _busy,
                  onPressed: !_signedIn ? null : _backupNow,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: AppButton(
                  label: 'Restore',
                  icon: Icons.cloud_download_outlined,
                  variant: AppButtonVariant.secondary,
                  loading: _busy,
                  onPressed: !_signedIn ? null : _restore,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _scheduleLabel(BackupSchedule schedule) => switch (schedule) {
    BackupSchedule.manual => 'Manual',
    BackupSchedule.daily => 'Daily',
    BackupSchedule.weekly => 'Weekly',
    BackupSchedule.monthly => 'Monthly',
  };

  static String _formatDate(DateTime time) {
    final local = time.toLocal();
    return '${local.year}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }

  static String _formatDateTime(DateTime time) {
    final local = time.toLocal();
    return '${_formatDate(local)} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }
}
