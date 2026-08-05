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

## Database (Drift/SQLite, schema v2)
- All monetary values are **integers in minor units** (12345 = ₱123.45). Decimal digits come from `CurrencyFormatter` (JPY=0, BHD=3, default 2). Never use `double` for money.
- Income/expense **categories live in the `accounts` table** (`kind = category`) — category spend is just a ledger aggregate, same as account balances.
- `accounts.opening_balance_minor` is informational only; the authoritative opening balance is a real "Opening Balance" transaction paired with the system account.
- Every write is validated by `DoubleEntryEngine` (debits == credits, ≥2 entries, positive amounts) and wrapped in `db.transaction(...)` for atomicity.
- `DatabaseSeeder` (idempotent, `onCreate`) seeds the Opening Balances system account + 32 default categories.
- **Gotcha**: editing tables/DAOs requires `dart run build_runner build` to regenerate the committed `.g.dart` files; schema changes need a version bump + migration step in `AppDatabase`.
- **Backup**: `BackupService` exports a portable JSON snapshot via a custom enum-aware `ValueSerializer` (drift 2.34 dropped its bundled backup API — do not rely on `ExportDatabase`/`ImportDatabase`). Round-trip is covered by `test/backup_service_test.dart`.
- **Security**: PIN is salted SHA-256 via `PinService` (pepper in `AppConstants`); `SecurityGate` wraps the app root. `local_auth` is v3 (flat params, no `AndroidOptions`). Native platform config lives in `ios/Runner/Info.plist`, `macos/Runner/*.entitlements`, `android/.../AndroidManifest.xml`.

## Conventions
- Linting: `flutter_lints` via `analysis_options.yaml`.
- Material 3 design system with design tokens in `lib/core/theme/` (`app_palette.dart`, `app_colors.dart`, `app_typography.dart`, `app_spacing.dart`, `app_radii.dart`, `app_shadows.dart`); Inter font family (bundled in `assets/fonts/`).
- Errors: all failures are `FinFlowException` subclasses (`ValidationException`, `DomainException`, `NotFoundException`, `DatabaseException`) — UI surfaces `message` in a snackbar, never leaks internals.
- Money parsing/formatting goes through `MoneyInputParser` and `CurrencyFormatter` in `core/utils/` — don't reimplement.
- Tests: widget tests use `test/helpers/widget_harness.dart` (overrides DB + providers); repositories tested against an in-memory DB.
