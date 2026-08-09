import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/app_providers.dart';
import '../../domain/profile.dart';

/// The user's profile (name + avatar), loaded from `app_settings`.
///
/// Writes go through [SettingsDao.set] so every change is timestamped and
/// enqueued into the sync outbox — the profile follows the user across
/// devices whenever cloud sync is enabled.
final profileProvider = NotifierProvider<ProfileController, Profile>(
  ProfileController.new,
);

class ProfileController extends Notifier<Profile> {
  @override
  Profile build() {
    final dao = ref.watch(settingsDaoProvider);
    dao.get(SettingsKeys.profileName).then((name) {
      if (name != null) state = state.copyWith(name: name);
    });
    dao.get(SettingsKeys.profilePicture).then((picture) {
      if (picture != null) state = state.copyWith(picture: picture);
    });
    return const Profile();
  }

  /// Saves the display name (trimmed). Empty clears the name.
  Future<void> setName(String name) async {
    final trimmed = name.trim();
    await ref
        .read(settingsDaoProvider)
        .set(SettingsKeys.profileName, trimmed);
    state = state.copyWith(name: trimmed);
  }

  /// Saves the avatar as a base64 data URI.
  Future<void> setPicture(String dataUri) async {
    await ref
        .read(settingsDaoProvider)
        .set(SettingsKeys.profilePicture, dataUri);
    state = state.copyWith(picture: dataUri);
  }

  /// Removes the avatar. Stored as an empty value (not a deleted row) so the
  /// removal propagates through op-log sync like any other value change.
  Future<void> clearPicture() async {
    await ref
        .read(settingsDaoProvider)
        .set(SettingsKeys.profilePicture, '');
    state = state.copyWith(picture: '');
  }
}
