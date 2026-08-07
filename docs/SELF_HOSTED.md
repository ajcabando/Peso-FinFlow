# FinFlow — Self-Hosted Backend & Migration Plan

> Status: **approved design** (2026-08-07). This document is the master plan for
> replacing the optional Supabase layer with a fully self-hosted stack. The API
> contract it depends on lives in **`docs/BACKEND_API.md`**; the Flutter-side
> sync today is described in **`docs/SYNC.md`** (which this plan supersedes
> once the migration lands).

---

## 1. Vision & non-negotiables

FinFlow is a **local-first, offline-first** personal finance platform.

- Every transaction is written to the **on-device Drift/SQLite database first**.
- The local database is **always authoritative**. The cloud is a *mirror* used
  only for: backup, multi-device synchronisation, web access, and restore after
  device loss.
- The app must be **100% usable with no internet**. No connectivity disables
  only cloud sync and cloud backup — nothing else.
- The backend is **self-hosted**. No Supabase, no Firebase, no vendor lock-in.
  Everything runs in Docker behind the user's existing nginx reverse proxy.

```
Flutter (Android / iOS / iPadOS / Web)
        │
        ▼
Local SQLite (Drift)  ─── source of truth
        │
        ▼
Double-Entry Accounting Engine
        │
        ▼
Sync Queue (operation log, local outbox)
        │
        ▼
REST API (NestJS) ──────► PostgreSQL
        │                  │
        ├──────────────────► MinIO (attachments, backups)
        │
        └──────────────────► Redis (optional: jobs, rate limiting)
```

### What this changes vs. today

| Area | Today (v0.2.0) | Target |
|---|---|---|
| Auth | Supabase Auth (email/password + phone OTP) | Self-hosted JWT + rotating refresh tokens, Argon2id |
| Sync protocol | Row-delta pull/push against PostgREST | **Operation log** (`POST /sync/push`, `GET /sync/pull`) |
| Cloud DB | Supabase Postgres (RLS) | Self-hosted Postgres behind the API only |
| Attachments | Local-only (never synced) | MinIO object storage, presigned URLs |
| Backup | Local file export/import | Encrypted cloud backups + scheduled + restore |
| Web | SQLite WASM (OPFS/IndexedDB) | Unchanged — same sync path as mobile |

---

## 2. Current-state analysis (what we keep, what we replace)

### Keep as-is (no change)

- **Drift local DB** (`lib/database/`) — tables, DAOs, migrations, seeder,
  deterministic `SeedIds`, tombstone triggers. The local schema stays the
  primary schema.
- **Double-entry engine** (`lib/features/transactions/domain/`) — pure Dart,
  balances always derived from `ledger_entries`, never cached. Preserved
  verbatim.
- **Repositories + Riverpod DI** — the repository pattern already exists and is
  the correct seam; the cloud refactor adds new repositories, never duplicates
  the existing ones.
- **All 193 tests** — they must stay green at every phase.
- **PWA/Web build** (`web/`, `Dockerfile`) — unchanged; the web target just
  talks to the new API the same way mobile does.

### Replace

- `supabase_flutter` dependency, `Supabase.initialize` in `lib/main.dart`,
  `SupabaseSyncRemote`, the Supabase auth wiring in
  `lib/features/sync/presentation/providers/sync_providers.dart`, and the
  Supabase schema in `supabase/migrations/0001_init.sql` (superseded by the
  server's Postgres migrations).
- `SyncEngine` row-delta protocol → operation-log engine (Section 6).

### Reuse with adaptation

- **`SyncRemote` abstraction** — the seam survives, but the contract changes
  from "row deltas" to "push/pull operations" (see `docs/BACKEND_API.md` §4).
  The in-memory `FakeSyncRemote` test doubles are re-purposed for the op-log
  fake.
- **`sync_meta` / `sync_tombstones` tables** — superseded by the outbox +
  cursors in schema v5 (Section 7). Tombstone *triggers* stay: they feed the
  outbox with DELETE operations.
- **`BackupService`** — the portable JSON snapshot becomes the *payload* that
  is encrypted and uploaded. The local export/import UX is unchanged.
- **`SyncSession`** — stays as the write-time user stamp; gains device-id and
  version stamps.

---

## 3. Infrastructure & Docker topology

The server has Docker, Docker Compose and nginx (reverse proxy) already.
**Nginx is not replaced.** FinFlow is one more Docker stack behind it:

```
                  ┌──────────────┐
  api.finflow...──►  nginx (host) │   TLS termination, rate limit at edge
                  └──────┬───────┘
                         │  proxy network (e.g. name: nginx-proxy)
                  ┌──────▼───────┐
                  │ finflow-api  │   the ONLY container reachable from nginx
                  └──────┬───────┘
                         │  internal network `finflow_net` (no published ports)
              ┌──────────┼───────────┐
        ┌─────▼────┐ ┌───▼───┐ ┌─────▼─────┐
        │ postgres │ │ minio │ │  redis    │   optional but recommended
        └──────────┘ └───────┘ └───────────┘
```

Rules:

1. `postgres`, `minio`, `redis` are on the **internal network only** — zero
   published ports, unreachable from the host LAN or the internet.
2. `finflow-api` joins both the internal network and a shared **proxy network**
   that nginx is also attached to. The proxy network name is configurable
   (`PROXY_NETWORK`); if nginx runs on the host (not a container), publish the
   API on `127.0.0.1:8080` instead and proxy to that.
3. Everything has **healthchecks**; the API waits for postgres (`pg_isready`)
   and minio before starting; migrations run as a one-shot `migrate` service
   that the API depends on (`condition: service_completed_successfully`).
4. Persistent **volumes**: `pgdata`, `minio-data`, `redis-data`.
5. MinIO exposes **no public bucket**. Attachments are uploaded/downloaded via
   API-issued **presigned URLs**.

### compose topology sketch

```yaml
networks:
  finflow_net:     { internal: true }
  proxy:           { name: ${PROXY_NETWORK:-nginx-proxy}, external: true }

services:
  migrate:
    build: ./server
    command: sh -c "node dist/drizzle/migrate.js"
    env_file: .env
    depends_on: { postgres: { condition: service_healthy } }
    networks: [finflow_net]

  finflow-api:
    build: ./server
    restart: unless-stopped
    env_file: .env
    depends_on:
      postgres: { condition: service_healthy }
      minio:    { condition: service_healthy }
      redis:    { condition: service_healthy }   # when enabled
      migrate:  { condition: service_completed_successfully }
    networks: [finflow_net, proxy]
    # no ports: — reachable only via the proxy network (or host nginx via 127.0.0.1:8080)

  postgres:
    image: postgres:17-alpine
    environment: { POSTGRES_USER, POSTGRES_PASSWORD, POSTGRES_DB }
    volumes: [pgdata:/var/lib/postgresql/data]
    healthcheck: { test: ["CMD-SHELL", "pg_isready -U $${POSTGRES_USER}"], interval: 5s }
    networks: [finflow_net]

  minio:
    image: minio/minio:latest
    command: server /data --console-address ":9001"
    volumes: [minio-data:/data]
    # `mc ready local` needs a preconfigured alias — use the image's built-in
    # HTTP health endpoint instead (curl ships in the minio image).
    healthcheck: { test: ["CMD", "curl", "-f", "http://localhost:9000/minio/health/live"], interval: 5s }
    networks: [finflow_net]

  redis:   # optional (JOBS_ENABLED=false drops this service)
    image: redis:7-alpine
    volumes: [redis-data:/data]
    healthcheck: { test: ["CMD", "redis-cli", "ping"], interval: 5s }
    networks: [finflow_net]

volumes: { pgdata: {}, minio-data: {}, redis-data: {} }
```

Full `docker-compose.yml` + `.env.example` ship with the server in Phase 1
(Section 11). Nginx server block example: `deploy/nginx-finflow-api.conf.example`.

---

## 4. Backend design — NestJS + Drizzle

### Stack decisions (locked 2026-08-07)

| Concern | Choice |
|---|---|
| Framework | **NestJS 11** (TypeScript, strict mode) |
| Data layer | **Drizzle ORM** + `node-postgres`; SQL-first, no runtime magic |
| Migrations | `drizzle-kit generate` → versioned SQL; applied by `migrate` service |
| Password hashing | **Argon2id** (`argon2` package, OWASP params: m=19456, t=2, p=1) |
| Auth tokens | JWT **access** (15 min) + **opaque rotating refresh tokens** (hashed at rest, bound to device) |
| Validation | `class-validator` + global `ValidationPipe` (whitelist, forbid non-whitelisted) |
| Logging | `pino` (structured JSON, request ids, no PII) |
| Config | `@nestjs/config` + **zod**-validated `.env` (fail fast at boot) |
| Email | `nodemailer` — generic SMTP via env vars (host/port/user/pass/secure) |
| Jobs | **BullMQ** on Redis (optional; disabled via `JOBS_ENABLED=false`) |
| Object storage | `minio` SDK (private bucket, presigned URLs) |
| Security | `helmet`, `@nestjs/throttler`, strict CORS allow-list, DTO validation everywhere |

### Module layout

```
server/
  src/
    main.ts                 # helmet, CORS, global pipes, pino logger, shutdown hooks
    config/env.validation.ts
    common/                 # guards, decorators, exception filter, pagination DTO
    users/                  # users table + service (no password leaks)
    auth/                   # signup/login/logout/refresh/me, verification, password reset
    devices/                # device registry + revocation
    sync/                   # op-log: push/pull controllers, conflict resolver, materialiser
    ledger/                 # read model for /ledger (balances are computed here, never stored)
    resources/              # /accounts /transactions /bills /budgets /tags /settings
    storage/                # MinIO client, presigned URLs, attachments
    backup/                 # backup metadata + blob endpoints (encrypted payloads pass through)
    jobs/                   # BullMQ: email queue, cleanup, (optional) server-side jobs
    health/                 # /health (liveness) + /health/ready (deps)
  drizzle/
    schema.ts               # Drizzle schema — single source of truth
    migrations/             # generated SQL migrations
  test/                     # Jest unit + supertest e2e (real Postgres via testcontainers)
```

### Cross-cutting

- **Every endpoint** is behind `AuthGuard` (JWT) except `auth/*`, `health/*`.
- **Errors** use a uniform envelope: `{ "error": { "code", "message", "requestId" } }`
  (details in `docs/BACKEND_API.md` §1). No stack traces, no SQL leaks.
- **Idempotency**: sync writes are idempotent by operation UUID; payment-style
  endpoints use `Idempotency-Key` headers where relevant.
- **Pagination**: cursor-based (op-log) and offset-based (read endpoints),
  always `LIMIT`-capped server-side.

---

## 5. Database design (PostgreSQL)

Managed **only** by the API. No direct exposure, ever. Drizzle schema in
`server/src/drizzle/schema.ts`; generated migrations in `server/drizzle/migrations`.

### Tables

**Identity & auth**

- `users` — `id uuid pk`, `email citext unique`, `password_hash`, `is_verified`,
  `verification_token_hash`, `created_at`, `updated_at`. (No phone OTP in v1 of
  the self-hosted backend — email/password only, per spec.)
- `password_reset_tokens` — `user_id fk`, `token_hash`, `expires_at`, `used_at`.
- `devices` — `id uuid pk`, `user_id fk`, `name`, `platform`, `app_version`,
  `last_sync_at`, `last_seen_at`, `revoked_at`, `created_at`.
  Index: `(user_id)`.
- `refresh_tokens` — `id uuid pk`, `user_id fk`, `device_id fk`, `token_hash`,
  `expires_at`, `revoked_at`, `replaced_by`. Rotation + revocation on logout /
  device revoke. Index: `(user_id, revoked_at)`.

**Sync (operation log — the core of the new engine)**

- `sync_ops` — the **append-only operation history**:
  - `seq bigserial pk` (pull cursor — monotonic, server-assigned)
  - `op_id uuid unique` (client-generated; idempotency key)
  - `user_id fk not null`, `device_id fk not null`
  - `entity text not null` (`account|transaction|bill|budget|tag|app_setting`)
  - `entity_id text not null`
  - `operation text not null` (`upsert|delete`)
  - `base_version int not null` (the version this op was based on — CAS)
  - `version int not null` (the version this op produces)
  - `payload jsonb not null` (full entity row, snake_case — mirrors local DB)
  - `updated_at timestamptz not null` (client timestamp for tie-breaks)
  - `deleted_at timestamptz null`
  - `created_at timestamptz not null default now()`
  - Indexes: `(user_id, seq)` for pull cursors; `(user_id, entity, entity_id,
    seq)` for entity lookups + latest-op reads. There is **deliberately NO
    unique `(user_id, entity, entity_id, version)` index** — the current state
    of an entity is the *latest-seq* op for it (seq is authoritative), and a
    LWW winner may legitimately share a version with an earlier loser (the
    version-unique index was dropped in migration `0002` because it 23505'd on
    exactly that). Push-time `pg_advisory_xact_lock` serialisation (below)
    makes the winner unambiguous.

**Current-state (materialised from ops — what the REST read endpoints serve)**

- `accounts`, `transactions`, `bills`, `budgets`, `tags`, `ledger_entries`,
  `transaction_tags` — mirror the local Drift tables 1:1, with **composite
  primary keys `(user_id, id)`** (migration `0003`; `transaction_tags` uses
  `(user_id, transaction_id, tag_id)`, `app_settings` uses `(user_id, key)`).
  Composite keys are mandatory, not cosmetic: the app seeds deterministic ids
  (system account + 32 categories from `SeedIds`, identical on every install),
  so the same id legitimately exists for many users — a global `id` PK would
  make any two users collide (`23505`) and lets unscoped lookups read/mutate
  another user's rows. **Every current-state query must be scoped
  `WHERE user_id = ? AND id = ?`.**
- A push transaction atomically writes the header op **and** its
  `ledger_entries` + `transaction_tags` rows so the invariant "every
  transaction has a balanced child set" holds server-side too. Soft-deleting a
  transaction also hard-deletes its children so derived balances never include
  a deleted transaction. Accounts are only ever soft-deleted (RESTRICT FKs
  from `ledger_entries.account_id`, `budgets.category_id`, `bills.account_id`).

**Storage & backups**

- `attachments` — `id uuid pk`, `user_id`, `transaction_id fk null`,
  `object_key` (MinIO path), `mime_type`, `size_bytes`, `sha256`,
  `uploaded_at null`, `created_at`. Blobs live in MinIO, never in Postgres.
  Confirm (`PATCH`) stats the object server-side before stamping `uploaded_at`.
- `backups` — `id uuid pk`, `user_id`, `device_id`, `object_key`, `size_bytes`,
  `sha256`, `uploaded_at null`, `created_at`. The payload is **client-encrypted**
  (Section 7); the server stores and returns it opaquely. Retention capped by
  `BACKUP_RETENTION` (pruned on confirm), blob size by `MAX_BACKUP_BYTES`.
  Migration `0005` adds `uploaded_at` to both.

> **Ops follow-up (Phase 8 jobs)**: a presigned PUT can be used without ever
> confirming, so rows with `uploaded_at IS NULL` older than ~24 h must be swept
> (delete row + `object_key` blob). Not yet implemented — tracked here so the
> storage-DoS residual from the confirm-time verification is closed.

### Why an operation log instead of row-delta sync

1. **Device-independent history** — the server can replay any device's state
   from scratch; new devices bootstrap with a clean `GET /sync/pull?cursor=0`.
2. **Ordering without clock trust** — the server assigns `seq`; the client
   cursor never skips or duplicates, regardless of client clock skew.
3. **Conflict resolution is explicit** — CAS on `base_version` + LWW on
   `version`/`updated_at`, decided server-side at push time (Section 6).
4. **Auditability** — every change is an immutable, reviewable record.

---

## 6. Sync protocol — operation log

Full wire contract: **`docs/BACKEND_API.md` §4**. Design summary:

### Operation envelope (per entity change)

```jsonc
{
  "opId": "uuid",                 // client-generated, idempotency key
  "entity": "transaction",
  "entityId": "txn-uuid",
  "operation": "upsert",          // | "delete"
  "baseVersion": 7,               // version this edit was based on (CAS)
  "version": 8,                   // version this edit produces
  "payload": { /* full row + transaction children */ },
  "updatedAt": "2026-08-07T…Z",   // client timestamp (tie-break only)
  "deletedAt": null               // set when operation == "delete"
}
```

### Push

- `POST /sync/push` takes a **batch** of ops (≤ 500); device identity comes
  from the access token and is verified against each op's `deviceId`. The
  server processes the batch in one transaction, ops sequentially:
  1. **Pre-validation (fail fast, before the transaction)**: every
     `transaction` upsert payload must pass the double-entry check
     (`assertBalancedLedger` — ≥ 2 entries, positive integer amounts, debits ==
     credits) and every payload is size-capped (100 KB). A violation aborts the
     **whole batch** with `409 LEDGER_IMBALANCE` / `400` and nothing is
     written — the client must fix the offending op and re-push everything.
  2. **Serialisation guard**: a per-`(user_id, entity, entity_id)`
     `pg_advisory_xact_lock` is acquired before each op's check — two
     concurrent pushes can never both pass CAS, for fresh *and* existing rows
     (a `SELECT … FOR UPDATE` on the current-state table cannot lock a row that
     does not exist yet). Ops are processed in a deterministic
     `(priority, entity_id)` order so lock acquisition can never deadlock
     (AB-BA).
  3. **Idempotency**: if `op_id` exists, skip (return its original `seq`).
  4. **CAS + LWW**: `base_version` > stored version, or LWW says the stored
     state wins (highest `version` → newest `updated_at` → smallest `op_id`),
     ⇒ the op is **rejected as a conflict** carrying `current` (the full
     current payload incl. children) so the client can re-base immediately.
     The winner is appended + materialised; **losers are never inserted**. A
     rejected (stale) loser is reported as a *conflict*, not an applied no-op:
     if its winner's `seq` were acked instead, the client's cursor would jump
     past the winning op and the two devices would silently diverge. Because
     of this, **conflicts never advance `serverCursor`**.   5. Response: `{ "applied": [ {opId, seq} ], "conflicts": [ {opId, current} ],
      "serverCursor": N|null }` where `serverCursor` = the max seq of applied
      ops, or `null` when nothing was applied (never `0` — that is the pull
      "fresh" sentinel).
  6. **Atomicity modes**: CAS/LWW conflicts are reported in-body and the
     non-conflicting ops still apply (partial application). Thrown errors
     (malformed payload, unbalanced ledger, FK violation `23503` → `409`
     `CONFLICT`) roll back the **entire batch** — a client receiving a 409
     must treat nothing in that batch as applied.
- The device is re-checked `FOR UPDATE` inside the transaction (revocation
  TOCTOU closure): a device revoked mid-push either has its in-flight push
  complete first (accepted window) or the push aborts with `403` before
  writing anything.
- On `conflicts`, the client re-pulls from its cursor, re-bases the losing
  entity locally (LWW, same rules), bumps its version, and retries once.

### Pull

- `GET /sync/pull?cursor=N&limit=1000` → ops with `seq > N`, oldest-first,
  grouped by entity with parents before children. Response carries
  `nextCursor` (0 if nothing left). The client applies ops to the local DB in a
  transaction: `upsert` replaces the row (children as a consistent set),
  `delete` hard-deletes the local row. Applied deletes are bookkept so the
  tombstone trigger does **not** re-queue them into the outbox (no loops).

### Deletes

- **Soft deletes only** in the cloud. The client never hard-deletes a synced
  row from the server's perspective — a delete is an op with
  `operation: "delete"`, `payload: null` and `deletedAt` set. Locally, the row
  is removed after the op is acknowledged (or immediately, with the tombstone
  trigger generating the delete op in the outbox — the trigger's
  `WHEN OLD.user_id IS NOT NULL` guard already excludes never-synced rows).
- The trigger stamps the delete op with `baseVersion = OLD.version` and
  `version = OLD.version + 1` (the v5 `version` column makes this possible),
  so the server's CAS sees it as the natural successor of the last upsert.

### Conflict resolution (canonical rules)

1. `base_version` CAS mismatch → **rebase** (client re-pulls, re-applies LWW).
2. Same base, competing writes → **highest version wins**.
3. Version equal → **newest `updated_at` wins**.
4. Still equal → lexicographically smallest `op_id` wins (deterministic).

These rules are implemented identically on both sides; the server's push-time
LWW resolution (with the row-lock serialisation guard) is the single point of
truth, and the client's resolver only matters for re-base after a conflict.

### Client outbox (local schema v5, Section 7)

- Every repository write that touches a synced table, when `SyncSession` is
  signed in, also appends an op to `sync_outbox` in the same transaction.
- The engine flushes the outbox on: sign-in, app resume, 2s debounce after any
  local write, 60s heartbeat, manual "Sync now".
- **`write local → update UI → queue op → return immediately`** — the UI never
  waits for the network.

---

## 7. Flutter client refactor plan

### New local schema (v5) — additive, backwards compatible

- `sync_outbox` table: `id`, `op_id`, `entity`, `entity_id`, `operation`,
  `base_version`, `version`, `payload`, `updated_at`, `deleted_at`,
  `created_at` (mirror of the wire envelope; written by repositories).
- `sync_meta` repurposed: `user_id` + `push_cursor` (last pushed `seq` via
  server ack) + `pull_cursor` (last applied `seq`). This is a **column-type
  change** in v5: the DateTime `last_push_at`/`last_pull_at` watermarks are
  replaced by integer `seq` cursors, and the old Supabase watermark values are
  discarded (the first op-log sync starts from cursor 0 and pushes every local
  row as `baseVersion 0` — no data is lost because the rows themselves are
  already in the local DB).
- `version` integer column (default 0) added to the six synced tables so the
  CAS base-version is available at write time.
- Tombstone triggers stay, but their body changes to insert **DELETE ops**
  into `sync_outbox` instead of `sync_tombstones`. Gotcha: `CREATE TRIGGER IF
  NOT EXISTS` never replaces an existing trigger, so the v5 migration must
  explicitly **DROP the six old triggers** before the new ones are created.
  `sync_tombstones` itself is **kept until the row-delta engine is removed in
  Phase 6** (dropping it earlier breaks the old engine's `_pushTombstones`),
  then dropped.
- Migration step in `AppDatabase` (`from < 5`) — no data transformation needed,
  all existing rows get `version = 0` and are picked up on next push as
  `baseVersion 0`.

### New/changed Dart modules

```
lib/features/sync/
  domain/sync_config.dart        # FINFLOW_API_URL define replaces SUPABASE_*; enabled = URL present
  domain/sync_status.dart        # + deviceId, deviceName, backup schedule state
  data/api/api_client.dart       # http wrapper: base URL, bearer refresh, retry-once, error mapping
  data/api/api_exception.dart    # maps {error.code} → FinFlowException subclasses
  data/auth/auth_service.dart    # signup/login/logout/refresh/me + token storage
  data/auth/token_store.dart     # secure storage (flutter_secure_storage on native, localStorage on web)
  data/sync/device_registry.dart # device_id (persisted uuid), platform, app_version, name
  data/sync/op_sync_engine.dart  # outbox flush → POST /sync/push → GET /sync/pull → apply
  data/sync/op_conflict_resolver.dart  # pure Dart LWW/CAS logic (unit-tested)
  data/sync/fake_sync_remote.dart      # test double (replaces FakeSyncRemote)
  data/backup/cloud_backup_service.dart  # encrypt snapshot → PUT presigned URL
  data/backup/backup_crypto.dart        # AES-256-GCM + PBKDF2 (pure Dart, web-safe)
  presentation/…                   # SyncBootstrap/SyncCard/sign-in sheet updated; devices UI; backup schedule UI
```

- **Dependencies added**: `http` (or `dio`), `flutter_secure_storage`,
  `device_info_plus`, `package_info_plus`, `cryptography` (AES-GCM/PBKDF2).
  **Removed**: `supabase_flutter`.
- `lib/main.dart` no longer initialises Supabase; `SyncConfig` reads
  `FINFLOW_API_URL`. With no define → fully local, exactly like today.
- **Repositories**: the six write paths stamp `userId` (existing) **and** append
  the outbox op inside the same `db.transaction(...)` — a single new dependency
  (a `SyncOutboxWriter` service injected like `SyncSession` is read today).

### Backup & restore (cloud)

- `CloudBackupService` reuses `BackupService.exportBackup()` bytes, then:
  1. Derive a 32-byte key from a **user-chosen backup passphrase** with
     PBKDF2-HMAC-SHA256 (≥ 310k iterations; Argon2id is preferable but lacks a
     pure-Dart web-safe implementation — revisit if a native-only build is
     acceptable).
  2. Encrypt with AES-256-GCM (random 12-byte nonce, AAD = user id).
  3. `POST /backups` → presigned PUT to MinIO → record metadata.
- Restore: `GET /backups/:id/url` → download → decrypt → `importBackup()`.
- **Schedules** (`manual | daily | weekly | monthly`): stored in `app_settings`;
  the client runs the backup job when online (same triggers as sync) — the
  server never needs to see plaintext data, preserving zero-knowledge and
  offline-first.
- The existing local export/import card is unchanged.

### Settings UI

- **Account & sync** card: server URL status, sign in/up, email, device list
  with **revoke**, "Sync now", last-synced.
- New **Cloud backup** card: passphrase setup, schedule picker, "Back up now",
  "Restore from backup".

### Web

- Identical sync path; IndexedDB/OPFS persistence already in place via
  `WasmDatabase`. `flutter_secure_storage` has no web implementation → token
  storage falls back to `shared_preferences`/localStorage (documented risk;
  refresh tokens remain revocable server-side).

---

## 8. Security

| Requirement | Implementation |
|---|---|
| HTTPS only | Terminated at nginx; API behind proxy; `secure` cookie/flag guidance in docs |
| Passwords | Argon2id (m=19456, t=2, p=1), never logged, never returned |
| Access tokens | JWT (HS256, strong random secret from env, 15 min TTL, `sub` + `device` + `jti`) |
| Refresh tokens | Opaque, **hashed at rest** (SHA-256), rotated on use, one-time, bound to `device_id`, revoked on logout/device revoke |
| Rate limiting | `@nestjs/throttler`: global (e.g. 300/min/IP) + strict auth (e.g. 5/min/IP + 10/hour/email) |
| CSRF | N/A for bearer-token APIs; kept in mind if cookie auth is ever added |
| Input validation | Global `ValidationPipe` + class-validator DTOs on every body/query/param |
| SQL injection | Parameterised queries via Drizzle everywhere (no string interpolation) |
| CORS | Explicit allow-list (`CORS_ORIGINS`); no `*` with credentials |
| Headers | `helmet` defaults |
| Secrets | `.env` only, gitignored; `.env.example` ships with placeholders; no keys in images |
| Object storage | Private bucket; presigned URLs, short expiry; server verifies ownership before issuing |
| Backups | Client-side AES-256-GCM encryption before upload (zero-knowledge) |

### App Store note

The current ASC submission states **"No Data Collected."** Shipping cloud sync
means the privacy questionnaire must be updated (account-based sync = data
linked to the user). This is a manual ASC UI step, tracked in
`dist/ASC_SUBMISSION_CHECKLIST.md` — do **not** change the store listing before
the backend is actually live.

---

## 9. Testing strategy

| Layer | Tooling | Covers |
|---|---|---|
| Server unit | Jest | Argon2/JWT/refresh rotation, **conflict resolver** (LWW + CAS tables), validation |
| Server integration | Jest + real Postgres (testcontainers) | sync push/pull round-trips, idempotency, cursors, children atomicity |
| Server e2e | supertest | auth flows (signup→verify→login→refresh→logout→revoke), device registry, backup endpoints |
| Flutter | Existing suite + new | `op_conflict_resolver_test.dart`, `op_sync_engine_test.dart` (fake remote), `cloud_backup_crypto_test.dart` (round-trip + tamper), auth service against a mocked `http.Client` |
| CI | GitHub Actions | `flutter analyze` + `flutter test`; `server: npm test` + docker-compose smoke |

The existing 193 Flutter tests must pass **throughout** the migration — the
row-delta engine is removed only when the op-log engine and its tests are
landed and green (Section 11, Phase 6).

---

## 10. REST API surface

Contract-first spec in **`docs/BACKEND_API.md`**. Endpoints:

```
Auth        POST /auth/signup · POST /auth/login · POST /auth/logout
            POST /auth/refresh · GET /auth/me
            POST /auth/password/reset · POST /auth/password/reset/confirm
Devices     GET /devices · DELETE /devices/:id
Sync        POST /sync/push · GET /sync/pull
Resources   GET/POST /accounts · GET/PATCH/DELETE /accounts/:id · …same for
            /transactions /bills /budgets /tags /settings (reads current-state)
Ledger      GET /ledger/accounts/:id/balance · GET /ledger/transactions/:id/entriesAttachments     POST /attachments · PATCH /attachments/:id (confirm upload) · GET /attachments/:id/url · DELETE /attachments/:id
Backups         POST /backups · GET /backups · GET /backups/:id/url · POST /backups/:id/restore
Health      GET /health · GET /health/ready
```

Read endpoints exist for web/future client convenience, but the **primary**
write path is always the local DB → op-log. `/ledger` balances are computed
server-side from `ledger_entries` — never from cached values.

---

## 11. Phased rollout (backward compatibility)

Every phase keeps the app shippable; the Supabase path stays the default until
the final phase flips the flag.

| Phase | Scope | Exit criteria |
|---|---|---|
| **0** | This plan + API contract (`docs/BACKEND_API.md`) | Reviewed/approved |
| **1** | `server/` scaffold: NestJS + Drizzle + docker-compose + `.env.example` + health + pino + helmet + throttler + migrate service | `docker compose up` → `/health/ready` 200; `npm test` green |
| **1 ✅ shipped 2026-08-07** | `server/` scaffold complete: NestJS 11 + Drizzle + node-postgres, full 15-table schema (migrations `0000`+`0001`), docker-compose (postgres/minio/redis/migrate/finflow-api, internal net + proxy net), zod env validation, pino request-ids, helmet, global throttler, uniform error envelope, unit + e2e suites (14 tests) | Verified: build clean; tests green; compose up → `/health` + `/health/ready` 200; migration upgrade path proven on a live volume; only `127.0.0.1:8080` published. Review fixes applied: 5xx masking, client `deviceId` as `devices.id` PK, `refresh_tokens.device_id` index, pool timeouts, RESTRICT-FK soft-delete invariant noted |
| **2** | Auth + devices: signup/login/logout/refresh/me, Argon2id, email verification (optional), password reset (SMTP), device registry + revoke | e2e auth suite green |
| **2 ✅ shipped 2026-08-07** | Auth + devices implemented: Argon2id (OWASP m=19456/t=2/p=1), JWT access (15 min, HS256, issuer/audience enforced) + opaque rotating refresh tokens (SHA-256 at rest, device-bound, reuse → whole-device chain revocation), email verification (optional, enforced 60-min TTL) + SMTP password reset via Nodemailer, device registry (client-supplied `deviceId` as PK) with owner-scoped revoke, per-IP/per-email brute-force limiting, DTO validation, uniform envelopes | Verified: build clean; 24 unit + 27 e2e (real Postgres); live curl flows. Review fixes: owner-scoped device revoke (was cross-user), login timing equaliser (no user enumeration), reset response no longer leaks account existence, guarded rotation UPDATE (no double-successor race), verification-token expiry enforced. Stack left running on 127.0.0.1:8080 with a generated JWT secret |
| **3 ✅ shipped 2026-08-07** | Op-log sync engine: `sync_ops` (migrations `0002`–`0004`), current-state mirror with **composite `(user_id, id)` PKs**, `POST /sync/push` + `GET /sync/pull`, `pg_advisory_xact_lock` CAS serialisation, LWW conflict resolver (server + pure-Dart-ported rules), parent-first pull ordering, atomic transaction children, LEDGER_IMBALANCE + FK-violation (`23503` → 409) handling, per-op payload cap (100 KB), 2 MB JSON body limit (shared bootstrap), serialised e2e (`maxWorkers: 1` — the suites share one test Postgres) | Verified: build clean; 36 unit + 49 e2e (real Postgres); live curl smoke (push/pull/LEDGER_IMBALANCE 409/device-mismatch 403); migration upgrade path 0000→0004 proven on a persisted volume; two-user same-category-id smoke (2 rows, 0 conflicts — regression for the global-PK bug). Review fixes: composite PKs (was global — cross-user collision + unscoped reads), deadlock-free lock ordering, fail-fast batch pre-validation, revoke TOCTOU closure, `attachments` FK CASCADE (was SET NULL — would break user-deletion cascade), 23503 diagnostic constraint name. Stack left running |
| **3** | Op-log sync: `sync_ops` + current-state tables, push/pull, conflict resolver, children atomicity, cursors | push/pull e2e suite green; replay-from-scratch test |
| **4 ✅ shipped 2026-08-07** | Storage + backup: MinIO module (presigned attachments/backups with two-step confirm), resource read/write endpoints (§5) that generate ops, `/ledger` derived balances, Redis-backed brute-force limiter + conditional health checks, pino log redaction | Verified: build clean; **40 unit + 85 e2e** (real Postgres + real MinIO); **31 live smoke checks**; compose config valid; stack healthy (postgres/minio/redis all up). Review fixes: confirm-time stat verification (404 never-uploaded / 400 over-limit, `MAX_BACKUP_BYTES`), MinIO probe hard timeout, pino req serializer strips query strings + auth headers, Redis `requirepass` conditional (wired; `REDIS_URL` must carry the password when set). Stack left running |
| **5** | Flutter auth swap: `ApiClient`/`AuthService`/token store/device registry behind `FINFLOW_API_URL` define; Supabase still default. Includes the **Supabase data-migration decision**: a one-time export/import script for existing cloud users, or an explicit "cloud data resets" notice (must be decided before go-live — see Key Decisions) | flutter analyze + 193 tests green; manual sign-in against local stack |
| **6** | Flutter op-log engine: schema v5, outbox writer, `OpSyncEngine`, conflict resolver; row-delta engine removed | new engine tests + full suite green; two-device manual test |
| **7** | Cloud backup client + UI; devices UI; schedule job | round-trip + tamper tests green |
| **8** | Hardening: rate-limit tuning, log redaction, e2e soak, docs, App Store privacy update | security checklist complete |

Supabase code is deleted in Phase 6–7 (not before): `supabase_flutter` dep,
`SupabaseSyncRemote`, `supabase/migrations/`, `docs/SYNC.md` (superseded).

---

## 12. Future-feature readiness

The architecture is chosen so these land without redesign:

- **Family/team/business accounts** — `users` + a future `memberships` table
  scoping `sync_ops.user_id` to a *workspace* id; ops already carry `entity` +
  `version`, so multi-writer CAS extends naturally.
- **Recurring/scheduled transactions** — an `entity = schedule` plus a BullMQ
  job; children semantics mirror transactions.
- **AI insights** — the op log is a ready audit stream; a future worker can
  consume `sync_ops` without touching the app.
- **Bank/CSV import** — import writes locally first, then flows through the
  same outbox as any other write.
- **Multi-currency** — already integer-minor + `currency_code` everywhere; the
  op payload carries the field.
- **Budget forecasting / plugin system** — server as a stable API surface with
  versioned contracts (`/v1` prefix recommended at go-live).

---

## 13. Key decisions log

| Date | Decision |
|---|---|
| 2026-08-07 | Self-hosted stack replaces Supabase: NestJS + Drizzle + Postgres + MinIO (+ Redis optional) |
| 2026-08-07 | **Operation-log sync** (per spec): `POST /sync/push` + `GET /sync/pull`, CAS + LWW, soft deletes |
| 2026-08-07 | Email via generic **SMTP** env config (Nodemailer); phone OTP dropped |
| 2026-08-07 | Backups client-side encrypted (AES-256-GCM, PBKDF2 passphrase key) before upload — server is zero-knowledge |
| 2026-08-07 | Phased rollout; Supabase remains the shipped default until the op-log client lands green |
| 2026-08-07 | Ops carry `deviceId` (verified against the JWT claim) — per the spec, even though the token is authoritative |
| 2026-08-07 | **Open decision**: migration of existing Supabase cloud data — one-time export/import vs. explicit reset (decide in Phase 5) |
| 2026-08-07 | Upload confirm is server-verified (`statObject`): 404 if never uploaded, 400 if the actual blob exceeds the declared/policy size — presigned PUTs cannot bound uploads |
| 2026-08-07 | Redis `requirepass` conditional in compose (`REDIS_PASSWORD`); when set, `REDIS_URL` must carry the password |

Next action: implement **Phase 5** (Flutter auth swap — `ApiClient`/
`AuthService`/token store behind `FINFLOW_API_URL`; decide the Supabase
cloud-data migration first — see Key Decisions).
