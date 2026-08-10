# Changelog

All notable changes to **FinFlow** are documented here. This project follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) conventions and uses the package version from `pubspec.yaml` (`0.2.0+1`).

## [Unreleased]

### Added

- **Profile** — set your display name and avatar photo (Settings → top card, or tap the dashboard avatar); the dashboard greets you by first name ("Good morning, Alain"). Photos are decoded with the native codec (HEIC included), resized to fit 384px and re-encoded as a compact JPEG, then stored as a small data URI in `app_settings` (`profile.*` keys) so the profile syncs across devices whenever cloud sync is on.
- **Update checking** — Settings → About now shows the real installed version (from package_info, no more hardcoded numbers) with a "Check for updates" action that queries the public GitHub releases feed (`ajcabando/Peso-FinFlow`); when a newer build exists an in-app dialog offers to open its release page (via `url_launcher`) and renders the release's "What's new" notes as markdown (`flutter_markdown`). Numeric semver comparison ignores `v` prefixes and build metadata; the check is gated when the installed version can't be read so it never claims a release is newer than an unknown version. A **silent launch-time check** pre-advertises an available update on the About card (no modal, no error toasts).
- **What's new banner** — a dismissible strip at the top of the dashboard that summarises recent changes (profile, update checker, sync & backups) with a link to the full changelog. It's shown once per content revision — dismissing persists `whatsnew.lastSeen` in `app_settings` (a syncing key, so dismissing once hides it everywhere) and the copy is compiled into the build, so it can never describe features an older build doesn't have.

### Fixed

- The shell's floating quick-actions FAB no longer covers page content: every tab already cleared it (96–120px bottom padding) except Settings, which now matches (96px), and the FAB is hidden on the Settings tab entirely.

### Test

- **254 Flutter tests** — profile greeting + edit flow, the update checker (version comparison, GitHub API parsing, unknown-version gate, silent launch-time check, About-card states), and the What's new banner (shows by default, dismiss persists the revision, stays hidden on relaunch, hidden when already seen).

## [0.2.0] — 2026-08-09

### Added — Self-hosted sync platform (Phases 1–9)

**Backend (`server/` — NestJS 11, Drizzle + Postgres, MinIO, Redis, Docker Compose)**

- **Auth** — email/password with Argon2id (OWASP params), 15-min JWT access tokens, opaque rotating refresh tokens bound to devices (reuse detection revokes the whole device chain), optional email verification + SMTP password reset, per-IP/per-email brute-force limiting (Redis-backed, fail-open).
- **Device registry** — every login registers a device; users can revoke access per device from the app.
- **Operation-log sync** — `POST /sync/push` + `GET /sync/pull`: idempotent ops with CAS on `base_version` + last-write-wins conflict resolution (version → updated_at → op_id), server-assigned cursors, parent-first pull order, per-entity advisory-lock serialisation, balanced-ledger validation mirrored from the Dart engine.
- **Resources API** — CRUD for accounts, transactions, bills, budgets, tags, settings (writes flow through the sync engine; `security.*`/`pin.*` keys rejected server-side).
- **Storage** — MinIO with presigned URLs; two-step upload confirm for attachments and backups with server-verified size limits and retention pruning.
- **Zero-knowledge backups** — cloud backups are client-encrypted (AES-256-GCM + PBKDF2 passphrase); the server never sees plaintext.
- Health/readiness endpoints (Postgres + MinIO + Redis checks), pino log redaction, `docker-compose.yml` stack with internal networking.

**Client (schema v5 — sync outbox + op-log engine)**

- **Op-log sync engine** — local `sync_outbox` fed by tombstone triggers; push→pull→converge with CAS + conflict resolution, 2s-debounced and heartbeat triggers.
- **Account & sync UI** — sign-in, device management, manual sync button; opt-in via `FINFLOW_API_URL` (no define = 100% local).
- **Encrypted cloud backups** — passphrase-protected backup with a configurable schedule (secure storage native / localStorage web), last-run tracking; safe for unattended runs.
- `supabase_flutter` removed — the self-hosted API replaces the Supabase path end to end.

### Fixed

- Ops hardening: strict money coercion in the materializer, duplicate `transactionTags` dedupe, generated ledger-entry id collision loop, opId-reuse-across-entities 409, `serverCursor` stays `null` when nothing applied, password-reset invalidates prior tokens.

### Test

- **223 Flutter tests** — unit, repository, widget, stress, plus op-sync engine, conflict resolver, backup crypto, backup schedule.
- **40 server unit + 88 e2e tests** against real Postgres + MinIO (cross-user regression, mixed-batch fail-fast, storage confirm paths).

## [0.1.0] — 2026-08-05

### Added — Phases 1–15

- **Accounting engine** — double-entry ledger (`ledger_entries`) where every transaction writes balanced debits/credits; balances are derived aggregates, never stored, so transfers and credit cards can never be double-counted.
- **Accounts** — cash, bank, debit/credit card, e-wallet, PayPal, crypto, investment, loan; opening balances recorded as balanced ledger transactions; detail page with per-account activity, edit, archive, guarded delete.
- **Transactions** — expense / income / transfer / refund entry with date & time pickers, categories, merchant, notes; full list with search and type filters; detail view; swipe actions.
- **Dashboard** — animated Net Worth hero (assets − liabilities), quick actions, monthly cash flow chart, spending by category, budgets overview, recent activity, bills card.
- **Analytics** — month picker with 12-month net worth history, income & spending breakdowns by category (donut charts + ranked lists).
- **Budgets** — monthly per-category limits with ledger-derived progress, over-budget highlighting, dashboard overview.
- **Bills & reminders** (Phase 8) — recurring bills with due-day tracking, "due soon / overdue / paid" states, one-tap mark-paid, dashboard card.
- **Reports & exports** (Phase 9) — month report with income/expense/net summary and category breakdown, exportable as CSV or styled PDF.
- **Backup & restore** (Phase 10) — portable full-database JSON snapshot (accounts, transactions, ledger, budgets, bills, settings) with identical behavior on web and native.
- **Security** (Phase 11) — optional 4–8 digit PIN lock (salted SHA-256), Touch ID / Face ID unlock on native, auto-lock on background.
- **Performance** (Phase 14) — windowed/paginated transaction list with database-level search and type filters; 50k+ row stress harness.
- **Design system** — Material 3 premium fintech theme: light/dark modes, Inter font, floating pill navigation, gradient hero cards, reusable components, dynamic account/category colors from a shared palette.

### Changed

- Web target ships SQLite WASM (`web/sqlite3.wasm` + `web/drift_worker.js`) so the database runs fully in the browser with File System API persistence.
- Dashboard and Accounts pages share a responsive account grid (`AccountCardGrid`) that adapts between a horizontal strip and a wrap grid by breakpoint.

### Fixed

- Widget test harness now overrides the dashboard's `billsProvider` stream to prevent hangs.
- Bills repository `update()` no longer routes through the insert path (was dropping `is_paid`/`updated_at`).
- Backup restore uses an enum-aware `ValueSerializer` (drift 2.34 removed its bundled backup API).

### Test

- **177 tests passing** — unit, repository, widget, backup round-trip, report exports, PIN service, bills, and performance stress.
- `flutter analyze` clean; web release build compiles.

## Roadmap

- **Phase 12 — AI insights**: rule-based insights first, then an AI provider once a key is available.
- **Phase 13 — Optional cloud sync**: Supabase + email/password, offline-first via `drift_supabase` (or the drift sync API), Local/Cloud toggle defaulting to Local.
