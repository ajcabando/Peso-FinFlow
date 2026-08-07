import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/app_button.dart';
import '../pages/sign_in_sheet.dart';
import '../providers/sync_providers.dart';

/// Settings section: cloud account, sync status and controls.
class SyncCard extends ConsumerWidget {
  const SyncCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(syncControllerProvider);
    final controller = ref.read(syncControllerProvider.notifier);
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (!status.enabled) {
      return SyncSectionCard(
        icon: Icons.cloud_off_outlined,
        tint: colors.onSurfaceVariant,
        title: 'Cloud sync not configured',
        subtitle:
            'Rebuild with SUPABASE_URL and SUPABASE_ANON_KEY to enable '
            'multi-device sync (see docs/SYNC.md).',
        action: null,
      );
    }

    if (!status.signedIn) {
      return SyncSectionCard(
        icon: Icons.cloud_outlined,
        tint: colors.primary,
        title: 'Sign in to sync',
        subtitle:
            'Back up and sync your data across devices. Everything stays '
            'local-first — signing in only mirrors it to your account.',
        action: AppButton(
          label: 'Sign in',
          icon: Icons.login,
          onPressed: () => showSignInSheet(context),
        ),
      );
    }

    final relative = status.lastSyncedAt == null
        ? 'Not synced yet'
        : 'Synced ${_relative(status.lastSyncedAt!)}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SyncSectionCard(
          icon: status.syncing
              ? Icons.cloud_sync_outlined
              : Icons.cloud_done_outlined,
          tint: colors.primary,
          title: status.email ?? 'Signed in',
          subtitle: status.error ?? relative,
          action: null,
          error: status.error != null,
        ),
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
                    context.showSnack('Signed out — data stays on this device');
                  }
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Last write wins when the same entry is edited on two devices.',
          style: textTheme.bodySmall?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  static String _relative(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

/// The leading icon + title/subtitle + optional action row used by the sync
/// section, styled to match the other settings cards.
class SyncSectionCard extends StatelessWidget {
  const SyncSectionCard({
    super.key,
    required this.icon,
    required this.tint,
    required this.title,
    required this.subtitle,
    required this.action,
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
                style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
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
