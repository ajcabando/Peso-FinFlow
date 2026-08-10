/// Content definition for the in-app "What's new" banner.
///
/// The banner is compiled into the build alongside the features it
/// describes, so it is self-gating: nobody sees it on an older build. Each
/// user dismisses it once per revision — bump [kWhatsNewRevision] whenever
/// the copy below changes so the banner is shown again in the next update.
library;

/// Bump whenever the banner copy changes to re-show it to every user.
const String kWhatsNewRevision = '2026.08.1';

/// The full changelog, opened from the banner footer.
const String kWhatsNewChangelogUrl =
    'https://github.com/ajcabando/Peso-FinFlow/blob/main/CHANGELOG.md';

/// The banner's subtitle.
const String kWhatsNewSubtitle = "Fresh from the latest build";

/// One short line per highlight — keep each under ~72 characters so the
/// banner stays compact on narrow phones.
const List<String> kWhatsNewItems = [
  'Profile — set a display name & avatar; the dashboard greets you by first name.',
  'Update checker — About shows your real version and checks for new releases.',
  'Sync & backups — self-hosted sync with encrypted, zero-knowledge cloud backups.',
];
