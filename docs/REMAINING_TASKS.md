# Remaining Tasks — FinFlow

> **Start here every session.** This is the single source of truth for what comes
> next. When you sit down to work on FinFlow, open this file first, pick the next
> unchecked item, and tick items off as they land.
>
> **Status: Backend complete (Phases 1–4 + hardening, shipped 2026-08-08).**
> Next up: **Phase 5 — the Flutter client migration to the self-hosted backend.**
>
> Master plan: `docs/SELF_HOSTED.md` · API contract: `docs/BACKEND_API.md` ·
> Product backlog (v0.2.0): `docs/NEXT_RELEASE.md`.

## How to use

1. Read the **Next up** section and start with the first unchecked item.
2. Mark `[x]` when a task lands; add a short note of what shipped.
3. New work discovered mid-session goes to the **Backlog** section.

---

## Next up (in order)

### Phase 5 — Flutter auth swap (currently blocked on the data decision below)

- [ ] Decide the **Supabase cloud-data migration** (open decision, bottom of file): one-time
      export/import script vs. explicit "cloud data resets" notice — must be decided before go-live.
- [ ] `lib/features/sync/domain/sync_config.dart` — `FINFLOW_API_URL` dart-define replaces
      `SUPABASE_URL`/`SUPABASE_ANON_KEY`; enabled = URL present, absent ⇒ fully local.
- [ ] `data/api/api_client.dart` — http wrapper: base URL, bearer attach, 401→refresh→retry-once, error mapping.
- [ ] `data/api/api_exception.dart` — maps `{error.code}` → `FinFlowException` subclasses.
- [ ] `data/auth/auth_service.dart` + `data/auth/token_store.dart` — signup/login/logout/refresh/me;
      `flutter_secure_storage` on native, localStorage fallback on web.
- [ ] `data/sync/device_registry.dart` — persisted `device_id`, platform, app version, device name.
- [ ] Add deps `http` (or dio), `flutter_secure_storage`, `device_info_plus`, `package_info_plus`; keep
      `supabase_flutter` as the default until Phase 6 lands.
- [ ] Settings → Account & sync card: server URL status, sign in/up, email, device list + revoke, Sync now.
- [ ] Exit criteria: `flutter analyze` clean + existing 193 tests green; manual sign-in against the local stack.

### Phase 6 — Flutter op-log engine (local schema v5)

- [ ] `sync_outbox` table + `version` columns on the six synced tables; migration `from < 5` (no data transform).
- [ ] Repoint tombstone triggers to insert DELETE ops into `sync_outbox` — must explicitly DROP the six old
      triggers first (`CREATE TRIGGER IF NOT EXISTS` never replaces).
- [ ] `sync_meta` → integer `push_cursor`/`pull_cursor` (replace DateTime watermarks).
- [ ] `OpSyncEngine` — outbox flush → `POST /sync/push` → `GET /sync/pull` → apply; triggers: sign-in, resume,
      2s debounce, 60s heartbeat, manual.
- [ ] `op_conflict_resolver.dart` — pure Dart LWW/CAS port of the server rules (unit tests).
- [ ] Repository write paths append the outbox op inside the same `db.transaction(...)`.
- [ ] Remove the row-delta engine (`SupabaseSyncRemote`, `SyncEngine`), `supabase_flutter` dep,
      `supabase/migrations/`, `docs/SYNC.md`.
- [ ] Exit criteria: new engine tests + full suite green; two-device manual sync test.

### Phase 7 — Cloud backup client + UI

- [ ] `backup_crypto.dart` — AES-256-GCM + PBKDF2 (≥310k iters) pure Dart, web-safe; round-trip + tamper tests.
- [ ] `cloud_backup_service.dart` — encrypt `BackupService` snapshot → `POST /backups` → presigned PUT → PATCH.
- [ ] Settings → Cloud backup card: passphrase setup, schedule picker (manual/daily/weekly/monthly), Back up now, Restore.
- [ ] Devices UI polish + "Sync now" / last-synced states.

### Phase 8 — Backend hardening follow-ups

- [ ] **Cleanup sweep job**: delete rows with `uploaded_at IS NULL` older than ~24 h (attachments + backups)
      AND their MinIO objects — closes the unconfirmed-upload storage-DoS residual (see `docs/SELF_HOSTED.md` §5).
- [ ] **Wire Redis auth end-to-end**: set `REDIS_PASSWORD` in the root `.env`, verify the compose `--requirepass`
      branch + auth-aware healthcheck work, and update `REDIS_URL` to carry the password.
- [ ] e2e soak run (repeat suite several times to shake flakes).
- [ ] App Store privacy questionnaire: "No Data Collected" is no longer accurate once sync ships — update
      `dist/ASC_SUBMISSION_CHECKLIST.md` + the ASC listing before going live.

---

## Open decisions

- **Supabase cloud-data migration (blocks Phase 5):** existing users have data in the Supabase cloud. Either
  (a) ship a one-time export/import script, or (b) ship a notice that cloud data resets when the new backend
  goes live. Local data is unaffected either way — this only concerns rows already pushed to Supabase.

---

## Backlog (parked / future)

- [ ] BullMQ background jobs (`JOBS_ENABLED`) — email queue, cleanup, server-side backup triggers.
- [ ] Redis-backed rate limiting across instances (limiter already supports it; wire `REDIS_URL`).
- [ ] Multi-currency, undo, scheduled transactions — product roadmap in `docs/NEXT_RELEASE.md` (P0).
- [ ] Recurring transactions (`entity = schedule`), bank/CSV import, AI insights — architecture already supports
      them without redesign (`docs/SELF_HOSTED.md` §12).
