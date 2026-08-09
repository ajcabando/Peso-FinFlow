/// The user's profile: a display name and an optional avatar picture.
///
/// Persisted in `app_settings` under `profile.*` keys, so it works fully
/// offline and — because those keys are not in the `security.*` local-only
/// namespace — syncs across devices when cloud sync is on.
class Profile {
  const Profile({this.name = '', this.picture = ''});

  /// Display name; empty when the user has not set one yet.
  final String name;

  /// Avatar picture as a base64 data URI (`data:image/jpeg;base64,…`),
  /// empty when unset.
  final String picture;

  bool get hasPicture => picture.isNotEmpty;

  /// The first word of the name — what the dashboard greeting uses
  /// ("Good morning, Alain").
  String get firstName {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '';
    return trimmed.split(RegExp(r'\s+')).first;
  }

  Profile copyWith({String? name, String? picture}) => Profile(
    name: name ?? this.name,
    picture: picture ?? this.picture,
  );
}
