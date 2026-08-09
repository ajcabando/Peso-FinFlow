import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_card.dart';
import '../pages/sign_in_sheet.dart';
import '../providers/sync_providers.dart';

/// Settings → Account & sync: cloud account, sync status, device list and
/// controls. Every state renders inside a standard [AppCard] so the section
/// matches the rest of Settings.
class SyncCard extends ConsumerWidget {
  const SyncCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(syncControllerProvider);
    final controller = ref.read(syncControllerProvider.notifier);
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (!status.enabled) {
      return AppCard(
        child: SyncSectionRow(
          icon: Icons.cloud_off_outlined,
          tint: colors.onSurfaceVariant,
          title: 'Cloud sync is off',
          subtitle:
              'This build has no sync server configured, so your data stays '
              'on this device. Build with --dart-define=FINFLOW_API_URL to '
              'enable sign-in and cloud backup (docs/SELF_HOSTED.md).',
        ),
      );
    }

    if (!status.signedIn) {
      return AppCard(
        child: SyncSectionRow(
          icon: Icons.cloud_outlined,
          tint: colors.primary,
          title: 'Sign in to sync',
          subtitle:
              'Back up and sync your data across devices. Everything stays '
              'local-first — signing in only mirrors it to your account.',
          action: AppButton(
            label: 'Sign in',
            icon: Icons.login,
            expand: false,
            onPressed: () => showSignInSheet(context),
          ),
        ),
      );
    }

    final relative = status.lastSyncedAt == null
        ? 'Not synced yet'
        : 'Synced ${_relative(status.lastSyncedAt!)}';
    final subtitle = status.conflictNeedsAttention
        ? 'Some changes need attention — sync now to resolve.'
        : status.error ?? relative;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SyncSectionRow(
            icon: status.syncing
                ? Icons.cloud_sync_outlined
                : status.conflictNeedsAttention
                ? Icons.error_outline
                : Icons.cloud_done_outlined,
            tint: status.conflictNeedsAttention ? colors.error : colors.primary,
            title: status.email ?? 'Signed in',
            subtitle: subtitle,
            error: status.error != null || status.conflictNeedsAttention,
          ),
          const SizedBox(height: AppSpacing.md),
          const Divider(height: 1),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  label: status.syncing ? 'Syncing…' : 'Sync now',
                  icon: Icons.sync,
                  variant: AppButtonVariant.secondary,
                  loading: status.syncing,
                  onPressed: status.syncing
                      ? null
                      : () => controller.syncNow(),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: AppButton(
                  label: 'Sign out',
                  icon: Icons.logout,
                  variant: AppButtonVariant.secondary,
                  onPressed: () async {
                    await controller.signOut();
                    if (context.mounted) {
                      context.showSnack(
                        'Signed out — data stays on this device',
                      );
                    }
                  },
                ),
              ),
            ],
          ),
          if (status.devices.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            const Divider(height: 1),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Devices',
              style: textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            for (final device in status.devices)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: Icon(
                  _platformIcon(device.platform),
                  color: colors.onSurfaceVariant,
                ),
                title: Text(
                  device.name,
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  '${device.platform.isEmpty ? '' : '${device.platform} · '}'
                  '${device.appVersion}'
                  '${device.current ? ' · this device' : ''}',
                  style: textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                trailing: device.current
                    ? null
                    : IconButton(
                        icon: Icon(
                          Icons.close_rounded,
                          color: colors.error,
                          size: 20,
                        ),
                        tooltip: 'Revoke this device',
                        onPressed: () async {
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (dialogContext) => AlertDialog(
                              title: const Text('Revoke device?'),
                              content: Text(
                                '${device.name} will be signed out and can no '
                                'longer sync this account.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(
                                    dialogContext,
                                  ).pop(false),
                                  child: const Text('Cancel'),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.of(
                                    dialogContext,
                                  ).pop(true),
                                  child: const Text('Revoke'),
                                ),
                              ],
                            ),
                          );
                          if (confirmed == true && context.mounted) {
                            await controller.revokeDevice(device.id);
                            if (context.mounted) {
                              context.showSnack('Device revoked');
                            }
                          }
                        },
                      ),
              ),
          ],
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.sync_lock_outlined,
                size: 14,
                color: colors.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Last write wins when the same entry is edited on two '
                  'devices.',
                  style: textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static IconData _platformIcon(String platform) => switch (platform) {
    'android' => Icons.smartphone,
    'ios' || 'ipados' => Icons.phone_iphone,
    'macos' => Icons.desktop_windows,
    'windows' => Icons.desktop_windows,
    'linux' => Icons.computer,
    'web' => Icons.language,
    _ => Icons.devices_other,
  };

  static String _relative(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

/// The leading icon + title/subtitle + optional action row shown inside the
/// sync card, styled to match the other settings cards.
class SyncSectionRow extends StatelessWidget {
  const SyncSectionRow({
    super.key,
    required this.icon,
    required this.tint,
    required this.title,
    required this.subtitle,
    this.action,
    this.error = false,
  });

  final IconData icon;
  final Color tint;
  final String title;
  final String subtitle;
  final Widget? action;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: tint.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(icon, color: tint, size: 22),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: textTheme.bodySmall?.copyWith(
                  color: error ? colors.error : colors.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        if (action != null) ...[
          const SizedBox(width: AppSpacing.sm),
          action!,
        ],
      ],
    );
  }
}
