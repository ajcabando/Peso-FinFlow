# Project knowledge

FinFlow — local-first, offline-first personal finance app (Android/iOS/iPadOS/Web). Core idea: a **double-entry accounting engine** — every transaction writes balanced debits/credits to a `ledger_entries` table, and account balances are *derived* aggregates, never stored.

## Quickstart
- Setup: Flutter 3.44+ is at `~/flutter` — `export PATH="$HOME/flutter/bin:$PATH"`, then `flutter pub get`
- Codegen (required after touching Drift tables/DAOs): `dart run build_runner build`
- Dev: `flutter run` (desktop/mobile) or `flutter run -d chrome` (web)
- Test: `flutter test` (currently **177 tests**: unit + repository + widget + stress)
- Lint: `flutter analyze` (must stay clean)
- Build: `flutter build web` → serve `build/web` (DB runs in SQLite WASM via `web/sqlite3.wasm` + `web/drift_worker.js`)

## Architecture
- **Feature-first clean architecture**: `lib/features/<feature>/{domain, data, presentation}` plus `core/` (theme, utils, errors), `database/` (Drift tables/DAOs/seeder), `shared/widgets/` (design system), `app/` (composition root, router, Riverpod providers).
- Dependency flow: **presentation → domain ← data → database → core**. Domain is pure Dart — the double-entry engine has zero Flutter/DB imports and is fully unit-tested.
- **Riverpod** is the DI/composition root (`lib/app/providers/app_providers.dart`). UI reads reactive `StreamProvider`s; repositories/DAOs are provided once. Tests override `databaseProvider` with an in-memory DB (`test/helpers/test_database.dart`).
- **go_router** with `StatefulShellRoute.indexedStack` (Dashboard / Accounts / Settings tabs).
- Key docs: `docs/architecture.md`, `docs/database.md`. Master roadmap is in `README.md`.
- Feature modules added since the original scaffold: `features/bills/` (recurring bills + mark-paid), `features/reports/` (month report, CSV/PDF export), `features/backup/` (portable JSON snapshot), `features/security/` (PIN lock + biometrics). Dashboard watches `billsProvider` — **widget tests must override it** (see `test/helpers/widget_harness.dart`).

## Performance & pagination
- The transactions list is **windowed** (30 rows per page, infinite scroll): `transactionsPage({from, to, search, type})` in `TransactionDao` + `TransactionListController`. DB-level search uses case-insensitive `LIKE` on merchant/note; `existsQuery` flags whether more rows remain.
- The `test/performance_stress_test.dart` harness seeds 50k+ transactions and asserts pagination + aggregate latency stays reasonable.

## Database (Drift/SQLite, schema v3)
- All monetary values are **integers in minor units** (12345 = ₱123.45). Decimal digits come from `CurrencyFormatter` (JPY=0, BHD=3, default 2). Never use `double` for money.
- Income/expense **categories live in the `accounts` table** (`kind = category`) — category spend is just a ledger aggregate, same as account balances.
- `accounts.opening_balance_minor` is informational only; the authoritative opening balance is a real "Opening Balance" transaction paired with the system account.
- Every write is validated by `DoubleEntryEngine` (debits == credits, ≥2 entries, positive amounts) and wrapped in `db.transaction(...)` for atomicity.
- `DatabaseSeeder` (idempotent, `onCreate`) seeds the Opening Balances system account + 32 default categories.
- **Gotcha**: editing tables/DAOs requires `dart run build_runner build` to regenerate the committed `.g.dart` files; schema changes need a version bump + migration step in `AppDatabase`.
- **Backup**: `BackupService` exports a portable JSON snapshot via a custom enum-aware `ValueSerializer` (drift 2.34 dropped its bundled backup API — do not rely on `ExportDatabase`/`ImportDatabase`). Round-trip is covered by `test/backup_service_test.dart`.
- **Security**: PIN is salted SHA-256 via `PinService` (pepper in `AppConstants`); `SecurityGate` wraps the app root. `local_auth` is v3 (flat params, no `AndroidOptions`). Native platform config lives in `ios/Runner/Info.plist`, `macos/Runner/*.entitlements`, `android/.../AndroidManifest.xml`.
- **App name (v0.1.0+6)**: Store/brand name is **Peso-FinFlow**. iOS display name = `ios/Runner/Info.plist` (`CFBundleDisplayName`); Android label = `AndroidManifest.xml`; macOS product name = `macos/Runner/Configs/AppInfo.xcconfig` (`PRODUCT_NAME`). In-app branding (dashboard header "FinFlow", CSV header) is separate and test-asserted. Note: renaming macOS `PRODUCT_NAME` renames the built artifact (`.app`/`.ipa`) — `dist` copies must follow the new name.

## Machine gotchas (this Mac)
- **Never symlink `~/Library/Developer/CoreSimulator` (or `~/Library/Developer/Xcode`) to another volume** — the sandboxed `CoreSimulatorService` cannot write through the redirect (EPERM), so simulator device creation fails and *every* iOS build (ibtool/actool) dies with `Failed to find or create execution context` / `Failed to find a suitable device`. This bit us on 2026-08-06 (data was redirected to `/Volumes/DATA/Dev/`); the fix was copying the data back to the real system-volume paths and removing the symlinks. The DATA copies still exist at `/Volumes/DATA/Dev/` if you need to restore anything. Xcode itself living on the DATA volume is fine — only the `~/Library/Developer/*` redirects break.
- iOS project is now **storyboard-free** (modern Flutter template): `UILaunchScreen` in `Info.plist`, no `Main.storyboard`/`LaunchScreen.storyboard`. This was required because this machine's CoreSimulator can't run ibtool.
- App Store upload: `dist/FinFlow-v0.1.0-appstore.ipa` (24 MB, App Store distribution signing, team 25FHU3ZF38). Upload via `xcrun altool --upload-app --type ios -f dist/FinFlow-v0.1.0-appstore.ipa -u <appleid> -p <app-specific-password>` or the Transporter app.

## iOS build & App Store (lessons learned)
- **Never remove `Main.storyboard`**: `FlutterSceneDelegate` needs `UISceneStoryboardFile: Main` to instantiate the `FlutterViewController`. A storyboard-free setup (dict-only) compiles, validates and uploads fine but renders a **blank screen and Dart never starts** on device/simulator. If it ever regresses, restore with `python3 tool/fix_ios_storyboard.py`. Symptom: app process alive, no crash, no DB created, black screen.
- **Screenshot workflow** (native, no web hacks): `flutter build ios --simulator --debug --dart-define=FINFLOW_DEMO_DATA=true --dart-define=FINFLOW_SCREEN=<analytics|transactions|accounts>` (the `FINFLOW_SCREEN` define in `main.dart` auto-navigates after launch; omit it for the dashboard). Install via `xcrun simctl install`, launch, `simctl io <udid> screenshot /tmp/x.png` (never write to the DATA volume — simctl can't). iPhone 15 Pro Max sim = native 6.7" 1290×2796; iPad 13" M4 sim → downscale 2064×2752 → 2048×2732 (PIL LANCZOS).
- **fl_chart implicit animations (`duration:`) hang the first frame on web** (and software-rendered sims): charts render a perpetual boot splash (`#c4c4c4`). The charts in `cash_flow_chart.dart`, `net_worth_trend_chart.dart`, `category_spend_section.dart` use `duration: Duration.zero` deliberately.
- Deployment target is **iOS 15.0** (Apple requires ≥15 by Spring 2027; also the minimum for `UILaunchScreen` dict + `UIColorName`).
- App Store name is **Peso-FinFlow** (bundle `com.finflow.finflow`). Build 2 was broken (no storyboard); build 3 fixed that; **build 4 is current** (switched the app icon to the user's `dist/Peso-FinFlow.png` design — 1254px white/ink-teal master; regenerate all sizes by downscaling it to `dist/finflow_icon_1024.png`, writing the 15 `Icon-App-*.png` iOS sizes, and running `tool/generate_platform_icons.py` for Android/macOS).

## App Store Connect automation
- Credentials live in **`~/.config/finflow/asc.env`** (gitignored, chmod 600): `ASC_ISSUER`, `ASC_KEY_ID`, `ASC_KEY_PATH` (`.p8` at `~/.config/finflow/AuthKey_*.p8`), `ASC_APP_ID` (Peso-FinFlow = `6798621116`). Created 2026-08-06 with an Admin API key. **Rotated 2026-08-06** — key `H3LV6VJW7W` (exposed in chat) replaced by `S97DXUDGG3`; old key revoked in ASC and local copies deleted.
- Helper: **`tool/asc_api.py`** — lists builds (`builds`), finds apps (`apps`), deep-dive on a build (`detail <build_id>`: processing state, beta review state, beta groups, export compliance), and polls until ready (`watch [build_number]`). Usage: `python3 tool/asc_api.py builds` / `detail e7d27ac4-…` / `watch 7`. Note: single-resource endpoints return `data` as a dict, list endpoints as an array.
- **Gotcha — low-S signatures**: JWT signing must use ES256 with **low-S normalization**. OpenSSL's random nonce produces high-S signatures ~50% of the time and Apple rejects them with HTTP 401 (`NOT_AUTHORIZED`) — the auth appears intermittently broken. Also strip DER's leading `0x00` padding bytes before padding r/s to 32 bytes. Both are handled inside `asc_api.py` — don't reimplement.
- Build 6 (`0.1.0 (6)`) was uploaded 2026-08-06 and is **VALID** on App Store Connect (min iOS 15.0, `usesNonExemptEncryption=False`, expires 2026-11-04). Uploads via `xcrun altool --upload-app` with the app-specific password (see chat history — do not store in repo).
- ASC metadata copy ready in **`dist/ASC_COPY.md`** (description, keywords, what's new, privacy answers) + **`dist/privacy-policy.html`** (host on GitHub Pages, e.g. `https://ajcabando.github.io/FinFlow/privacy-policy.html`). Screenshots + 1024px icon packaged in `dist/Peso-FinFlow-ASC-assets.zip`.

## Conventions
- Linting: `flutter_lints` via `analysis_options.yaml`.
- Material 3 design system with design tokens in `lib/core/theme/` (`app_palette.dart`, `app_colors.dart`, `app_typography.dart`, `app_spacing.dart`, `app_radii.dart`, `app_shadows.dart`); Inter font family (bundled in `assets/fonts/`).
- Errors: all failures are `FinFlowException` subclasses (`ValidationException`, `DomainException`, `NotFoundException`, `DatabaseException`) — UI surfaces `message` in a snackbar, never leaks internals.
- Money parsing/formatting goes through `MoneyInputParser` and `CurrencyFormatter` in `core/utils/` — don't reimplement.
- Tests: widget tests use `test/helpers/widget_harness.dart` (overrides DB + providers); repositories tested against an in-memory DB.
