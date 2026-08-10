import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../domain/whats_new_content.dart';
import '../providers/whats_new_providers.dart';

/// A compact, dismissible "What's new" strip shown at the top of the
/// dashboard. Appears once per content revision (see [kWhatsNewRevision]);
/// dismissing persists the revision in `app_settings` so it never nags
/// again, and "See the full changelog" opens the repo's CHANGELOG.md.
class WhatsNewBanner extends ConsumerWidget {
  const WhatsNewBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // null = the persisted revision is still loading — render nothing so a
    // returning user never sees the banner flash before it hides.
    final visible = ref.watch(whatsNewControllerProvider);
    if (visible != true) return const SizedBox.shrink();

    final theme = context.theme;
    final gradient =
        theme.extension<FinFlowTheme>()?.heroGradient ??
        const [Color(0xFF9C6BFF), Color(0xFF6D5DF6)];

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, -10 * (1 - t)),
          child: child,
        ),
      ),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: gradient,
                    ),
                    borderRadius: BorderRadius.circular(13),
                    boxShadow: [
                      BoxShadow(
                        color: gradient.last.withValues(alpha: 0.35),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.auto_awesome_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "What's new",
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        kWhatsNewSubtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Dismiss',
                  onPressed: () =>
                      ref.read(whatsNewControllerProvider.notifier).dismiss(),
                  icon: const Icon(Icons.close_rounded, size: 20),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            for (final (index, item) in kWhatsNewItems.indexed)
              Padding(
                padding: EdgeInsets.only(
                  bottom: index == kWhatsNewItems.length - 1
                      ? 0
                      : AppSpacing.sm,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(colors: gradient),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        item,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            TextButton.icon(
              onPressed: () => _openChangelog(context),
              icon: const Icon(Icons.open_in_new_rounded, size: 15),
              label: const Text('See the full changelog'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openChangelog(BuildContext context) async {
    final opened = await launchUrl(
      Uri.parse(kWhatsNewChangelogUrl),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && context.mounted) {
      context.showSnack("Couldn't open the changelog.");
    }
  }
}
