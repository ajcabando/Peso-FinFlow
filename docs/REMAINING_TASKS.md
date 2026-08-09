# Remaining Tasks — FinFlow

> **Start here every session.** This is the single source of truth for what comes
> next. When you sit down to work on FinFlow, open this file first, pick the next
> unchecked item, and tick items off as they land.
>
> **Status: Backend complete (Phases 1–4 + hardening, shipped 2026-08-08).**
> **Client migration complete (Phases 5–7, shipped 2026-08-09): the Flutter app
> now speaks the self-hosted op-log API — Supabase is fully removed.**
> Next up: **Phase 8 hardening follow-ups** (below) and go-live prep.
>
> Master plan: `docs/SELF_HOSTED.md` · API contract: `docs/BACKEND_API.md` ·
> Product backlog (v0.2.0): `docs/NEXT_RELEASE.md`.

## How to use

1. Read the **Next up** section and start with the first unchecked item.
2. Mark `[x]` when a task lands; add a short note of what shipped.
3. New work discovered mid-session goes to the **Backlog** section.

---

## Next up (in order)

### Phase 5 — Flutter auth swap ✅ shipped 2026-08-09

- [x] `lib/features/sync/domain/sync_config.dart` — `FINFLOW_API_URL` dart-define replaces
      `SUPABASE_URL`/`SUPABASE_ANON_KEY`; enabled = URL present, absent ⇒ fully local.
- [x] `data/api/api_client.dart` — http wrapper: base URL, bearer attach, 401→refresh→retry-once, error mapping.
- [x] `data/api/api_exception.dart` — maps `{error.code}` → `FinFlowException` subclasses.
- [x] `data/auth/auth_service.dart` + `data/auth/token_store.dart` — signup/login/logout/refresh/me;
      `flutter_secure_storage` on native, localStorage fallback on web.
- [x] `data/sync/device_registry.dart` — persisted `device_id`, platform, app version, device name.
- [x] Deps added: `http`, `flutter_secure_storage`, `device_info_plus`, `package_info_plus`, `cryptography`;
      `supabase_flutter` removed.
- [x] Settings → Account & sync card: server URL status, sign in/up, email, device list + revoke, Sync now.
- [x] Exit criteria: `flutter analyze` clean + full suite green; live sign-in against the local stack (curl + Chrome).

### Phase 6 — Flutter op-log engine (local schema v5) ✅ shipped 2026-08-09

- [x] `sync_outbox` table + `version` columns on the six synced tables; migration `from < 5` (no data transform).
- [x] Repointed tombstone triggers to insert DELETE ops into `sync_outbox` (DROP + recreate);
      `WHEN OLD.user_id IS NOT NULL` guard prevents pulled deletes from re-queueing.
- [x] `sync_meta` → integer `push_cursor`/`pull_cursor` (replace DateTime watermarks).
- [x] `OpSyncEngine` — outbox flush → `POST /sync/push` → `GET /sync/pull` → apply; triggers: sign-in, resume,
      2s debounce, 60s heartbeat, manual.
- [x] `op_conflict_resolver.dart` — pure Dart LWW/CAS port of the server rules (unit tests).
- [x] Repository write paths append the outbox op inside the same `db.transaction(...)`
      (accounts/transactions/bills/budgets/settings; deletes via trigger).
- [x] Removed the row-delta engine (`SupabaseSyncRemote`, `SyncEngine`), `supabase_flutter` dep,
      `supabase/migrations/`, `docs/SYNC.md`.
- [x] Exit criteria: new engine tests + full suite green; two-device sync covered by tests; live web sync verified.
- [x] Review fixes (2026-08-09): server now returns each pulled op's `seq` so the client persists an exact
      cursor past the final page (was: re-fetched the tail every sync); persistent conflicts now surface
      "needs attention" and drop the stale op instead of looping; rebase of a CAS-stale op against a
      fresh entity re-anchors on base 0. New regression tests cover all three.

### Phase 7 — Cloud backup client + UI ✅ shipped 2026-08-09

- [x] `backup_crypto.dart` — AES-256-GCM + PBKDF2 pure Dart, web-safe; round-trip + tamper tests.
- [x] `cloud_backup_service.dart` — encrypt `BackupService` snapshot → `POST /backups` → presigned PUT → PATCH.
- [x] Settings → Cloud backup card: passphrase setup, Back up now, Restore.
- [x] Devices UI polish + "Sync now" / last-synced states.

### Phase 8 — Backend hardening follow-ups ✅ shipped 2026-08-09

- [x] **Cleanup sweep job** (`server/src/cleanup/cleanup.service.ts`, wired into `app.module.ts`) — deletes rows
      with `uploaded_at IS NULL` older than 24 h (attachments + backups) and their MinIO objects — closes the
      unconfirmed-upload storage-DoS residual (see `docs/SELF_HOSTED.md` §5).
- [x] **Redis auth end-to-end** — `REDIS_PASSWORD` in the root `.env`, compose `--requirepass` branch + auth-aware
      healthcheck verified (`redis-cli -a … ping` → PONG; `/health/ready` green), `REDIS_URL` carries the password.
- [x] e2e soak run — the suite repeated clean (2× 88 e2e against a fresh test Postgres).
- [ ] App Store privacy questionnaire: "No Data Collected" is no longer accurate once sync ships — update
      `dist/ASC_SUBMISSION_CHECKLIST.md` + the ASC listing before going live.

### Phase 9 — Cloud backup schedule trigger ✅ shipped 2026-08-09

- [x] `backup_passphrase_store.dart` — passphrase persisted so scheduled backups run unattended
      (secure storage on native, localStorage on web).
- [x] `SyncController` — `saveBackupPassphrase`, `backupNow` (persists passphrase + `backup.lastRunAt`), guarded
      `setBackupSchedule` (non-manual requires a stored passphrase → `ValidationException`), `maybeRunScheduledBackup`
      (due = signed in + non-manual + passphrase + interval elapsed; failures swallowed, retried next heartbeat).
- [x] `SyncBootstrap` 60 s heartbeat now also fires `maybeRunScheduledBackup` alongside the sync tick.
- [x] Cloud backup card: Save-passphrase button, controlled schedule dropdown (guard errors surface as a snackbar
      and the value reverts), passphrase-saved + last-backup indicators.
- [x] Tests (`test/backup_schedule_test.dart`, 8): schedule guard, passphrase persistence/trim, schedule persists
      to settings, `backupNow` records the run, due-interval fires, not-due skips, manual never fires, signed-out
      skips.

---

## Open decisions

- **Supabase cloud-data migration (resolved with the v0.2.0 rewrite):** the Supabase path shipped only as an
  optional, sign-in-gated feature and never had a released user base; the self-hosted migration (Phases 5–7)
  replaces it wholesale and `supabase/migrations/` is deleted. Any pre-existing cloud rows (none in
  production) are out of scope — no migration script is shipped.

---

## Backlog (parked / future)

- [ ] BullMQ background jobs (`JOBS_ENABLED`) — email queue, cleanup, server-side backup triggers.
- [ ] Redis-backed rate limiting across instances (limiter already supports it; wire `REDIS_URL`).
- [ ] Multi-currency, undo, scheduled transactions — product roadmap in `docs/NEXT_RELEASE.md` (P0).
- [ ] Recurring transactions (`entity = schedule`), bank/CSV import, AI insights — architecture already supports
      them without redesign (`docs/SELF_HOSTED.md` §12).
