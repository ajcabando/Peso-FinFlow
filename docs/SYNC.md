# Cloud sync (Supabase)

FinFlow stays **local-first**: the on-device Drift database is the source of
truth and the app is fully usable offline with no account. Signing in from
**Settings → Account & sync** mirrors your data to your Supabase account so
it follows you across devices. Sync is **optional** — without credentials
compiled in, the app behaves exactly as before.

## How it works

**Schema v4** added the sync plumbing without touching existing reads:

- `user_id` (nullable) on `accounts`, `transactions`, `bills`, `budgets`,
  `tags`, `app_settings` — `null` means "local-only" until a sign-in adopts
  the row. Repositories stamp the current user at write time
  (`SyncSession.instance.userId`).
- `sync_meta` — per-user push/pull watermarks (`updated_at` cursors).
- `sync_tombstones` — written by SQLite `AFTER DELETE` triggers whenever a
  synced row is hard-deleted, so deletes propagate across devices without
  soft-delete columns polluting every query.
- `sync_engine.dart` runs the cycle: **push** local rows changed since the
  last push (only when the cloud copy isn't newer — last-write-wins) →
  **pull** cloud rows changed since the last pull → repeat until converged.
  A winning transaction uploads/downloads its ledger entries + tags as one
  consistent set (`replaceTransactionChildren`).
- `DatabaseSeeder` now uses **deterministic ids** (`SeedIds`) for the system
  account and the 32 default categories, so two devices never duplicate the
  Opening Balances account or "Salary". Older installs are re-pointed to the
  canonical ids by `SeedReconciler` during the v3→v4 migration.

Triggers: sign-in, app resume, a 2s debounce after any local write
(`db.tableUpdates`), a 60s heartbeat, and the manual **Sync now** button.

### What syncs / what does not

| Synced | Not synced |
|---|---|
| accounts (incl. categories), transactions + ledger entries, bills, budgets, tags, non-secret app settings (theme, currency) | `security.*` settings (PIN hash stays device-local), attachments (local file paths / blob URLs are device-specific) |

### Known limitations

- **Last-write-wins**: if the *same* row is edited on two devices, the newer
  edit replaces the older one wholesale — no per-field merge, no conflict UI.
- **Client clocks**: ordering uses `updated_at` written by the client. A
  device with a badly skewed clock can mis-order writes (documented; not an
  issue for normal personal use).
- **Sign-out keeps data**: rows remain on the device (owned by the account
  that created them). A *different* account signing in later will adopt
  un-owned local rows — same-owner usage is assumed.

## Setting it up (one time, ~10 minutes)

1. **Create a project** at https://supabase.com (free tier is fine).
2. **Run the schema**: open the SQL editor and paste the contents of
   `supabase/migrations/0001_init.sql` (or `supabase db push` with the CLI).
   This creates the 8 tables, Row Level Security policies (every user only
   sees their own rows) and delta-sync indexes.
3. **Enable sign-in methods** under *Authentication → Providers / Sign In*:
   - **Email** — toggle on. Email confirmations optional.
   - **Phone** — toggle on **and** configure an SMS provider (Supabase's
     built-in SMS or Twilio/Vonage/MessageBird). Without a provider, the
     phone-OTP flow fails with a clear message.
4. **Copy the project URL + anon (publishable) key** from *Project Settings
   → API*. The anon key is safe to embed — RLS keeps data private.

## Building with sync enabled

```sh
flutter build web --release --pwa-strategy=offline-first \
  --dart-define=SUPABASE_URL=https://<project-ref>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<your-anon-key>
```

Mobile builds use the same defines. Without them the app runs fully local.

## Testing

```sh
flutter test test/sync_engine_test.dart      # engine: adoption, push/pull, LWW, tombstones, children
flutter test test/sync_migration_test.dart   # deterministic seeds, reconciler, tombstone triggers
```

The engine is tested against an in-memory `FakeSyncRemote`, so the suite
needs no network or real Supabase project.

## File map

```
lib/features/sync/
  domain/sync_config.dart        # dart-define config; disabled when absent
  domain/sync_status.dart        # UI state model
  data/sync_remote.dart          # cloud interface (fake-able)
  data/supabase_sync_remote.dart # PostgREST implementation
  data/sync_engine.dart          # adopt / push / pull / LWW / tombstones
  presentation/providers/…       # Riverpod wiring + SyncController (auth + status)
  presentation/widgets/…         # SyncBootstrap (background triggers), SyncCard (settings)
  presentation/pages/sign_in_sheet.dart  # email/password + phone OTP
lib/core/sync_session.dart       # current user id read at write time
supabase/migrations/0001_init.sql # cloud schema + RLS
```
