# FinFlow Backend API — Contract (v1)

> Contract-first specification for the self-hosted NestJS backend. This file is
> the source of truth for the wire protocol; implementation must not diverge
> from it without updating this document. Master plan: **`docs/SELF_HOSTED.md`**.
>
> Version: `v1` (2026-08-07). All routes are prefixed `/v1` at go-live; during
> development the prefix is configurable (`API_PREFIX`, default `/v1`).

## 0. Conventions

- **Auth**: `Authorization: Bearer <access_token>` on every endpoint except
  `auth/*` and `health/*`.
- **Content type**: `application/json` (bodies and responses). MinIO blob
  transfers use their own content types via presigned URLs.
- **Timestamps**: ISO-8601 UTC (`2026-08-07T09:30:00.000Z`). Clients send UTC.
- **Money**: integers in minor units (12345 = ₱123.45), matching the local DB.
  Never floats.
- **Ids**: UUIDs (v4) for server entities; clients keep their existing
  string ids for synced entities (`entity_id` is opaque text).
- **Pagination**: cursor-based for the op log, offset-based (`page`/`limit`,
  max 100) for read endpoints.
- **Rate limits**: global 300 req/min/IP; auth endpoints 5 req/min/IP and
  10 req/hour/email. `429` responses carry `Retry-After`.

## 1. Error envelope

All errors (4xx/5xx) return:

```jsonc
{
  "error": {
    "code": "VALIDATION_FAILED",   // machine-readable, stable
    "message": "password must be at least 8 characters",
    "requestId": "7f2c…"           // correlation id, also in X-Request-Id header
  }
}
```

| Code | HTTP | Meaning |
|---|---|---|
| `VALIDATION_FAILED` | 400 | DTO validation failed (`details` array included) |
| `UNAUTHORIZED` | 401 | Missing/expired access token, or invalid refresh token |
| `FORBIDDEN` | 403 | Valid token, not allowed (e.g. another user's device) |
| `NOT_FOUND` | 404 | Resource or entity not found |
| `CONFLICT` | 409 | CAS/version conflict (sync), duplicate email, device revoked |
| `TOO_MANY_REQUESTS` | 429 | Rate limited |
| `INTERNAL` | 500 | Unexpected — never leak internals |

No stack traces, no SQL text, no PII in errors.

---

## 2. Auth

> ✅ **Implemented (Phase 2, 2026-08-07)** — `server/src/auth`, `users`, `mail`.
> Verified: 24 unit + 27 e2e tests; live curl flows against the running stack.
> Notes: verification tokens are enforced to the 60-minute TTL the email
> promises; refresh-token reuse detection revokes the whole device chain (a
> client that loses a refresh *response* and retries the old token is logged
> out — an accepted OWASP tradeoff).

Email/password only. Argon2id server-side. Access token TTL 15 min; refresh
tokens are opaque, one-time, rotated on use, hashed at rest, bound to
`(user, device)`.

### `POST /auth/signup`

```jsonc
// Request
{ "email": "ada@example.com", "password": "correct-horse-battery-staple" }
// 201 Created
{
  "user": { "id": "uuid", "email": "ada@example.com", "isVerified": false },
  "verification": { "sent": true, "expiresInSeconds": 3600 }  // only when SMTP configured
}
```

- `EMAIL_VERIFICATION_REQUIRED=true` (default **false**): sign-up returns
  `201` + `verification.sent: true`; the account cannot log in until verified.
  With `false`, accounts are immediately usable and `verification.sent` may
  still be true (informational email) or false (SMTP not configured — 503 on
  the email-only paths, auth still works).
- Validation: email format, password ≥ 8 chars (and ≤ 128).

### `POST /auth/login`

```jsonc
// Request — device fields are required (first login registers the device)
{
  "email": "ada@example.com",
  "password": "…",
  "deviceId": "uuid",            // client-generated, persisted per install
  "deviceName": "Ada's iPhone",
  "platform": "ios",             // android | ios | ipados | web | macos
  "appVersion": "0.2.0"
}
// 200 OK
{
  "accessToken": "jwt…",              // 15 min
  "expiresIn": 900,
  "refreshToken": "opaque…",          // one-time
  "user": { "id": "uuid", "email": "ada@example.com", "isVerified": true }
}
```

- Existing device with same `deviceId` is re-activated (clears `revoked_at`,
  updates metadata) and its old refresh tokens are revoked.
- Revoked-device login is **not** blocked for the same `deviceId` (it's a
  re-auth of that install), but a *different* device logging into an account
  that revoked it stays revoked until it logs in again — revocation is a
  session-level kill, per spec.
- Failed attempts: throttled (5/min/IP + 10/hour/email).

### `POST /auth/refresh`

```jsonc
{ "refreshToken": "opaque…" }
// 200 OK
{ "accessToken": "jwt…", "expiresIn": 900, "refreshToken": "opaque…" /* rotated */ }
```

- The presented token is revoked (hashed match) and replaced by a new one.
  Reuse of an already-rotated token ⇒ `401 UNAUTHORIZED` and the whole
  refresh-token chain for that device is revoked (token-reuse detection).

### `POST /auth/logout`

```jsonc
{ "refreshToken": "opaque…" }   // optional — if absent, all of the device's tokens are revoked
// 204 No Content
```

- Also updates `devices.last_seen_at`. Client clears its local session.

### `GET /auth/me`

```jsonc
// 200 OK
{ "user": { "id": "uuid", "email": "ada@example.com", "isVerified": true },
  "device": { "id": "uuid", "name": "Ada's iPhone", "platform": "ios", "appVersion": "0.2.0" } }
```

### `POST /auth/password/reset`

```jsonc
{ "email": "ada@example.com" }
// 202 Accepted — always (no user enumeration)
{ "sent": true }
```

- Emails a one-time reset link/token (SMTP). Token hashed at rest, 30 min TTL.

### `POST /auth/verify-email`

```jsonc
{ "token": "…" }
// 204 No Content
```

- Marks the account verified (single-use token, enforced 60-minute expiry).

### `POST /auth/password/reset/confirm`

```jsonc
{ "token": "…", "newPassword": "…" }
// 204 No Content
```

- Revokes all refresh tokens for the user's devices; access tokens expire
  naturally (≤ 15 min).

---

## 3. Devices

> ✅ **Implemented (Phase 2, 2026-08-07).** Device revocation is owner-scoped:
> deleting another user's device id returns 404 (never confirms existence).

### `GET /devices`

```jsonc
// 200 OK
{ "devices": [
  { "id": "uuid", "name": "Ada's iPhone", "platform": "ios", "appVersion": "0.2.0",
    "lastSyncAt": "2026-08-07T…Z", "revokedAt": null, "current": true }
] }
```

### `DELETE /devices/:id`

```jsonc
// 204 No Content
```

- Revokes the device: all its refresh tokens die, future pushes from it are
  rejected (`403 FORBIDDEN`). Cannot revoke the *current* device via this
  endpoint (use `logout`).

---

## 4. Sync — operation log

> ✅ **Implemented (Phase 3, 2026-08-07)** — `server/src/sync`.
> Verified: 36 unit + 49 e2e (real Postgres); live curl flows. Current-state
> tables use **composite `(user_id, id)` primary keys** — the app seeds
> deterministic ids on every install, so the same id legitimately belongs to
> many users.

The heart of the protocol. Design rationale in `docs/SELF_HOSTED.md` §6.

### Operation envelope

```jsonc
{
  "opId": "uuid",
  "entity": "account | transaction | bill | budget | tag | app_setting",
  "entityId": "opaque client id",
  "deviceId": "uuid",
  "operation": "upsert | delete",
  "baseVersion": 7,
  "version": 8,
  "payload": { /* full entity row, snake_case, mirrors the local Drift row */ },
  "updatedAt": "2026-08-07T09:30:00.000Z",
  "deletedAt": null
}
```

- **`deviceId`** is the client's install id (same value used at login). The
  server verifies it matches the JWT `device` claim — the envelope field
  exists per the spec, the token is the authority.
- **`payload` for `transaction`** includes the children as a consistent set:
  `{ …txn fields…, "ledgerEntries": [ … ], "transactionTags": [ … ] }`. The
  server persists header + children atomically — a transaction op is never
  half-applied. For `operation: "delete"` the `payload` is `null`.
- **`app_setting`** `entityId` is the settings key. `security.*` keys are
  excluded client-side (never leave the device), as today.
- `baseVersion` of a fresh row is `0`. New rows always arrive as
  `{ baseVersion: 0, version: 1 }`.

### `POST /sync/push`

```jsonc
// Request (batch ≤ 500 ops; deviceId from the access token, not the body)
{
  "ops": [ /* Operation envelopes */ ]
}
// 200 OK
{
  "applied": [ { "opId": "uuid", "seq": 1042 } ],
  "conflicts": [ { "opId": "uuid", "current": { /* latest server state for entityId */ } } ],
  "serverCursor": 1042   // null when NOTHING was applied (all conflicted)
}
```

Server processing (one DB transaction, ops processed sequentially):

0. **Pre-validation (before the transaction — fail fast)**: every
   `transaction` upsert payload must pass the double-entry check (≥ 2 entries,
   positive integer amounts, debits == credits) and every payload is size-capped
   (100 KB). A violation aborts the **whole batch** with `409 LEDGER_IMBALANCE`
   / `400` and nothing is written. Money/amount fields are **strict**: a value
   that is present but not a safe integer (e.g. a JSON string from a bigint
   serialisation) is rejected with `400 VALIDATION_FAILED`, never silently
   coerced (a silent `0` would corrupt balances). Duplicate `transactionTags`
   are deduped; duplicate ledger-entry ids are regenerated; a reused `op_id`
   across entities is `409 CONFLICT`; any `23505` duplicate-key violation is
   mapped to `409 CONFLICT`, never a `500`.
1. **Serialisation guard**: a per-`(user_id, entity, entity_id)`
   `pg_advisory_xact_lock` serialises concurrent pushes — two devices can never
   both pass the CAS check, for fresh *and* existing rows (a `SELECT … FOR
   UPDATE` cannot lock a row that does not exist yet). Ops are processed in
   deterministic `(priority, entity_id)` order, so lock acquisition never
   deadlocks.
2. **Idempotent by `op_id`** — already-seen ops are skipped and their original
   `seq` returned in `applied`. An `op_id` that was already used for a
   DIFFERENT `(entity, entity_id, operation)` is a client bug and rejects the
   batch with `409 CONFLICT` (a silent ack would leave the second entity
   permanently unmaterialised).
3. **CAS**: if `base_version` > stored version for `(entity, entity_id)` →
   conflict. The op is rejected and the server returns `current` so the client
   can re-base.
4. **Stale (`base_version` ≤ stored but LWW says stored wins)**: resolve
   deterministically — highest `version` wins → newest `updated_at` wins →
   smallest `op_id` wins. The winner is appended; losers are **never
   inserted**. A stale loser is reported as a **conflict** (carrying
   `current`), not an `applied` no-op: acking the winner's `seq` instead would
   jump the client's cursor past the winning op and the devices would silently
   diverge. Consequently **conflicts never advance `serverCursor`** — the
   client re-pulls from its own cursor and re-bases from `conflicts[].current`.
   `serverCursor` is the max seq of `applied` ops; when **nothing** was applied
   it is `null` (never `0` — `0` is the "nothing since the beginning" sentinel
   on pull, conflating the two would make a naive client re-pull everything).
5. Each accepted op appends to `sync_ops` (server-assigned `seq`) and updates
   the current-state row (with children when `entity == transaction`).
6. **Atomicity modes**: CAS/LWW conflicts are reported in-body and the
   non-conflicting ops still apply (partial application). Thrown errors
   (malformed payload, unbalanced ledger, FK `23503` → `409` `CONFLICT`) roll
   back the **entire batch** — a client receiving a 409 must treat nothing in
   that batch as applied.
7. The device row is re-checked `FOR UPDATE` inside the transaction, so a
   device revoked mid-push cannot sneak writes in (TOCTOU closure).

Client retry after conflicts:

1. `GET /sync/pull?cursor=<ownCursor>` to fetch everything the server has
   past the client's last-known cursor.
2. Re-apply those ops locally (LWW, same rules — a local edit that was already
   pushed and acked never regresses).
3. For each conflicted entity, recompute the op from the now-current local
   state with `baseVersion = current.version`, `version = current.version + 1`.
4. Re-push once. If a conflict persists (rare, another device raced again),
   surface a "needs attention" sync state rather than looping forever.

### `GET /sync/pull?cursor=1042&limit=1000`

```jsonc
// 200 OK
{
  "ops": [ /* ops with seq > cursor, oldest first, parents before children */ ],
  "nextCursor": 2042,     // 0 when no more ops remain
  "truncated": false
}
```

- Pull pages are **repeatable**: the same `cursor` always returns the same ops
  (`seq` is immutable). `nextCursor == 0` ⇒ caught up.
- The client applies ops locally in one transaction: `upsert` → insert/replace
  row (+ children), `delete` → hard-delete the local row. Applied deletes are
  marked so the tombstone trigger does **not** re-queue them into the outbox.
- A fresh device bootstraps with `cursor=0` and replays the whole history
  (server keeps it indefinitely; an optional retention job can compact
  tombstones past N days under a `COMPACT_HISTORY_DAYS` env).

Conflict rules recap (canonical, must match the client resolver):

1. `base_version` CAS mismatch → rebase.
2. Highest `version` wins.
3. Equal version → newest `updated_at` wins.
4. Equal both → lexicographically smallest `op_id` wins.

---

## 5. Resources (read endpoints)

Current-state reads for web/API consumers. Writes to these endpoints are **not**
the primary path (the app writes locally → op log) but are provided for
server-side tooling and future web-only clients; they internally generate ops
for the signed-in device.

Standard collection contract (same shape for all six):

```jsonc
// GET /accounts?page=1&limit=50
{ "items": [ /* current-state rows, deleted_at null only */ ],
  "page": 1, "limit": 50, "total": 132, "hasMore": true }
```

| Endpoint | Notes |
|---|---|
| `GET/POST /accounts` · `GET/PATCH/DELETE /accounts/:id` | Includes categories (`kind`) and system account, like local. **Composite keys**: every `:id` lookup MUST be scoped `WHERE user_id = ? AND id = ?` (the same id legitimately exists for many users), and every read MUST filter `deleted_at IS NULL` |
| `GET/POST /transactions` · `GET/PATCH/DELETE /transactions/:id` | `GET /transactions/:id` includes `ledgerEntries` + `transactionTags` |
| `GET/POST /bills` · `GET/PATCH/DELETE /bills/:id` | |
| `GET/POST /budgets` · `GET/PATCH/DELETE /budgets/:id` | |
| `GET/POST /tags` · `GET/PATCH/DELETE /tags/:id` | |
| `GET/PUT /settings` · `GET/PUT /settings/:key` | Non-secret keys only; `security.*` rejected server-side too |

Soft deletes: `DELETE` marks `deleted_at`, never removes rows (matches the sync
model).

---

## 6. Ledger

Balances are **always derived** from `ledger_entries` — the server stores no
cached balance.

```jsonc
// GET /ledger/accounts/:id/balance
{ "accountId": "uuid", "balanceMinor": 124500, "currencyCode": "PHP",
  "asOf": "2026-08-07T09:30:00.000Z" }

// GET /ledger/transactions/:id/entries
{ "transactionId": "uuid", "entries": [
  { "id": "uuid", "accountId": "uuid", "direction": "debit", "amountMinor": 50000, "currencyCode": "PHP" },
  { "id": "uuid", "accountId": "uuid", "direction": "credit", "amountMinor": 50000, "currencyCode": "PHP" }
] }
```

- The server refuses to accept a `transaction` op whose payload entries do not
  balance (debits == credits, ≥ 2 entries, positive amounts) — same invariant
  as the Dart `DoubleEntryEngine`. Non-balanced payloads return
  `409 CONFLICT` with `code: LEDGER_IMBALANCE`.

---

## 7. Attachments (MinIO)

Blobs never touch Postgres. The API issues short-lived presigned URLs.

```jsonc
// POST /attachments  →  201
// Request
{ "transactionId": "uuid", "mimeType": "image/jpeg", "sizeBytes": 412345,
  "sha256": "hex…" }
// Response
{ "attachment": { "id": "uuid", "transactionId": "uuid", "mimeType": "image/jpeg",
    "sizeBytes": 412345, "sha256": "hex…", "createdAt": "…" },
  "uploadUrl": "https://minio…presigned-put…", "expiresInSeconds": 900 }

// GET /attachments/:id/url  →  200
{ "downloadUrl": "https://minio…presigned-get…", "expiresInSeconds": 3600 }

// DELETE /attachments/:id  →  204  (removes object + row)
```

- The presigned PUT is one-shot with a server-side size policy
  (`MAX_ATTACHMENT_BYTES`, default 25 MB). After upload the client calls
  `PATCH /attachments/:id` with `{ "uploaded": true }` to confirm.
- **Confirm verifies the object server-side** (a presigned PUT cannot bound
  the actual upload size): the object must exist — `404` if the blob was
  never uploaded — and its real size must fit both the declared `sizeBytes`
  and the policy cap. An over-limit blob is deleted from MinIO and the
  request returns `400`; the row is only stamped `uploadedAt` after that
  check passes.

---

## 8. Backups

Backups are **client-encrypted before upload** (AES-256-GCM, passphrase-derived
key — see `docs/SELF_HOSTED.md` §7). The server treats the payload as opaque
bytes in MinIO.

```jsonc
// POST /backups  →  201  — two-step, identical to attachments:
// POST creates the metadata + returns a one-shot presigned PUT URL, the
// client uploads the raw .finflowblob, then PATCHes { uploaded: true }.
{ "backup": { "id": "uuid", "sizeBytes": 812345, "sha256": "hex…",
    "createdAt": "…", "deviceName": "Ada's iPhone" },
  "uploadUrl": "https://minio…presigned-put…", "expiresInSeconds": 900 }

// GET /backups?page=1&limit=50
{ "items": [ /* newest first */ ], "page": 1, "limit": 50, "hasMore": false }

// GET /backups/:id/url  →  200
{ "downloadUrl": "https://minio…presigned-get…", "expiresInSeconds": 3600 }

// POST /backups/:id/restore  →  202
{ "status": "accepted" }
```

- `restore` is an async ack: the *client* downloads the blob, decrypts with the
  user's passphrase, and calls the local `importBackup()`. The server ack
  exists for audit/notifications (BullMQ email on completion where enabled).
- **Schedules** (`manual|daily|weekly|monthly`) live in `app_settings`
  (`backup.schedule`), executed client-side when online — the server never
  sees plaintext. A `daily` schedule with no backup in >26h surfaces a
  reminder in the Settings card.
- Retention: `BACKUP_RETENTION` (default 10) — oldest client-triggered or
  server job deletes extras (server can delete objects it owns; it cannot read
  them).
- Confirm (`PATCH /backups/:id`) verifies the blob exactly like attachments:
  `404` if never uploaded, `400` if the actual size exceeds the declared
  `sizeBytes` or `MAX_BACKUP_BYTES` (default 100 MB) — the row is marked
  uploaded only after the check passes.

---

## 9. Health

```jsonc
// GET /health  → 200 { "status": "ok", "uptimeSeconds": 123 }
// GET /health/ready  → 200
{ "status": "ok", "checks": { "postgres": "up", "minio": "up", "redis": "up" } }
// → 503 with { "status": "degraded", "checks": { "postgres": "down" } }
```

Used by Docker healthchecks and nginx upstream checks.

---

## 10. Env reference (server)

See `server/.env.example` for the full annotated file. Minimum surface:

```
NODE_ENV=production
API_PREFIX=/v1
PORT=8080
DATABASE_URL=postgres://finflow:…@postgres:5432/finflow
JWT_ACCESS_SECRET=<64+ random chars>
JWT_ACCESS_TTL=900
ARGON2_MEMORY=19456
ARGON2_ITERATIONS=2
ARGON2_PARALLELISM=1
EMAIL_VERIFICATION_REQUIRED=false
SMTP_HOST=…  SMTP_PORT=587  SMTP_USER=…  SMTP_PASS=…
SMTP_FROM="FinFlow <no-reply@…>"
APP_URL=https://finflow.example.com
CORS_ORIGINS=https://finflow.example.com,https://app.finflow.example.com
MINIO_ENDPOINT=minio  MINIO_PORT=9000  MINIO_ACCESS_KEY=…  MINIO_SECRET_KEY=…
MINIO_BUCKET=finflow
REDIS_URL=redis://redis:6379
JOBS_ENABLED=false
THROTTLE_TTL=60  THROTTLE_LIMIT=300
MAX_ATTACHMENT_BYTES=26214400
BACKUP_RETENTION=10
MAX_BACKUP_BYTES=104857600
```

Secrets never appear in logs, images, or this file. `drizzle-kit` migrations
are applied by the `migrate` service (see `docs/SELF_HOSTED.md` §3).

---

## 11. Versioning & stability

- All routes behind `/v1`. Breaking changes bump the prefix; additive changes
  (new fields/endpoints) do not.
- Server responses never remove fields a client depends on within a major
  version.
- The op envelope (`opId/entity/entityId/deviceId/operation/baseVersion/
  version/payload/updatedAt/deletedAt`) is frozen for v1 — clients and
  server must agree on it.
