import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/app_providers.dart';
import '../../domain/whats_new_content.dart';

/// Whether the "What's new" banner should be shown on the dashboard.
///
/// `null` while the persisted revision is still loading (the banner renders
/// nothing until resolved, so returning users never see a flash); `true`
/// until the user dismisses it; `false` once [kWhatsNewRevision] has been
/// persisted in `app_settings` (`whatsnew.lastSeen`). The key syncs like
/// any other non-secret setting, so dismissing once hides it everywhere.
final whatsNewControllerProvider =
    NotifierProvider<WhatsNewController, bool?>(WhatsNewController.new);

class WhatsNewController extends Notifier<bool?> {
  @override
  bool? build() {
    final dao = ref.watch(settingsDaoProvider);
    // Same "default then async-flip" pattern as the theme/profile
    // controllers — the read resolves before the user can interact.
    dao.get(SettingsKeys.whatsNewLastSeen).then((lastSeen) {
      state = lastSeen == kWhatsNewRevision ? false : true;
    });
    return null;
  }

  /// Hides the banner now and persists the revision so it stays hidden.
  Future<void> dismiss() async {
    state = false;
    await ref
        .read(settingsDaoProvider)
        .set(SettingsKeys.whatsNewLastSeen, kWhatsNewRevision);
  }
}
