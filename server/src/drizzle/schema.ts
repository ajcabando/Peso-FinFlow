/**
 * FinFlow backend schema — single source of truth for the PostgreSQL database.
 *
 * Mirrors the design in docs/SELF_HOSTED.md §5 and the local Drift schema
 * (snake_case columns, integers in minor units for money). The API is the only
 * thing that ever talks to these tables — PostgreSQL is never exposed.
 *
 * Entity tables (accounts, transactions, …) carry `version` + `deleted_at`
 * for the operation-log sync protocol (docs/BACKEND_API.md §4). Their primary
 * keys are `text` because client rows use opaque string ids (including the
 * deterministic seed ids from the app, e.g. the system account).
 */
import {
  bigint,
  bigserial,
  boolean,
  foreignKey,
  index,
  integer,
  jsonb,
  pgTable,
  primaryKey,
  text,
  timestamp,
  uniqueIndex,
  uuid,
} from 'drizzle-orm/pg-core';

// ---------------------------------------------------------------------------
// Identity & auth (Phase 2 consumes these)
// ---------------------------------------------------------------------------

export const users = pgTable(
  'users',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    // Stored lowercased by the auth service; the unique index enforces it.
    email: text('email').notNull(),
    passwordHash: text('password_hash').notNull(), // Argon2id
    isVerified: boolean('is_verified').notNull().default(false),
    verificationTokenHash: text('verification_token_hash'),
    createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
    updatedAt: timestamp('updated_at', { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => [uniqueIndex('users_email_unique').on(t.email)],
);

export const passwordResetTokens = pgTable(
  'password_reset_tokens',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    userId: uuid('user_id')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    tokenHash: text('token_hash').notNull(),
    expiresAt: timestamp('expires_at', { withTimezone: true }).notNull(),
    usedAt: timestamp('used_at', { withTimezone: true }),
    createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => [index('password_reset_tokens_user_idx').on(t.userId)],
);

export const devices = pgTable(
  'devices',
  {
    // The CLIENT-generated install id IS the identity (docs/BACKEND_API.md §2,
    // §4): login registers/re-activates the device with this id and every sync
    // op envelope carries it. No defaultRandom — the server stores the id the
    // client chose, so "re-activate device with same deviceId" works.
    id: uuid('id').primaryKey(),
    userId: uuid('user_id')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    name: text('name'),
    platform: text('platform'), // android | ios | ipados | web | macos
    appVersion: text('app_version'),
    lastSyncAt: timestamp('last_sync_at', { withTimezone: true }),
    lastSeenAt: timestamp('last_seen_at', { withTimezone: true }),
    revokedAt: timestamp('revoked_at', { withTimezone: true }),
    createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => [index('devices_user_idx').on(t.userId)],
);

export const refreshTokens = pgTable(
  'refresh_tokens',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    userId: uuid('user_id')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    deviceId: uuid('device_id').references(() => devices.id, { onDelete: 'cascade' }),
    tokenHash: text('token_hash').notNull(), // SHA-256 of the opaque token
    expiresAt: timestamp('expires_at', { withTimezone: true }).notNull(),
    revokedAt: timestamp('revoked_at', { withTimezone: true }),
    replacedBy: uuid('replaced_by'),
    createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => [
    index('refresh_tokens_user_revoked_idx').on(t.userId, t.revokedAt),
    index('refresh_tokens_device_idx').on(t.deviceId),
  ],
);

// ---------------------------------------------------------------------------
// Sync — append-only operation log (the core of the new engine)
// ---------------------------------------------------------------------------

export const syncOps = pgTable(
  'sync_ops',
  {
    // Server-assigned pull cursor — monotonic, clock-independent ordering.
    seq: bigserial('seq', { mode: 'number' }).primaryKey(),
    opId: uuid('op_id').notNull(), // client-generated idempotency key
    userId: uuid('user_id')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    deviceId: uuid('device_id')
      .notNull()
      .references(() => devices.id, { onDelete: 'cascade' }),
    entity: text('entity').notNull(), // account|transaction|bill|budget|tag|app_setting
    entityId: text('entity_id').notNull(), // client row id (text, opaque)
    operation: text('operation').notNull(), // upsert|delete
    baseVersion: integer('base_version').notNull(), // CAS guard
    version: integer('version').notNull(), // version this op produces
    payload: jsonb('payload'), // full entity row (null for deletes)
    updatedAt: timestamp('updated_at', { withTimezone: true }).notNull(), // client clock (tie-break)
    deletedAt: timestamp('deleted_at', { withTimezone: true }),
    createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => [
    uniqueIndex('sync_ops_op_id_unique').on(t.opId),
    index('sync_ops_user_seq_idx').on(t.userId, t.seq),
    index('sync_ops_entity_idx').on(t.entity, t.entityId),
    // Entity lookups + push-time `SELECT … FOR UPDATE` serialisation.
    index('sync_ops_user_entity_seq_idx').on(
      t.userId,
      t.entity,
      t.entityId,
      t.seq,
    ),
    // NOTE: deliberately NO unique (user, entity, entity_id, version). The
    // current state of an entity is the LATEST-seq op for it (append-only
    // history, seq is authoritative). A LWW winner may legitimately share a
    // version with an earlier loser, and seq order disambiguates.
  ],
);

// ---------------------------------------------------------------------------
// Current-state mirror tables (materialised from ops; read endpoints serve
// these). Children of transactions are replaced as a consistent set.
// ---------------------------------------------------------------------------

// NOTE ON KEYS: entity tables use a COMPOSITE primary key `(user_id, id)`.
// Client row ids are opaque and — critically — the app seeds deterministic
// ids (system account + 32 default categories from `SeedIds`, identical on
// EVERY install), so the same id legitimately exists for many users. A global
// `id` PK would make any two users collide (23505) and lets unscoped queries
// read/mutate another user's rows. Every query must scope by user_id.

export const accounts = pgTable(
  'accounts',
  {
    // INVARIANT: the sync materializer must SOFT-delete accounts (UPDATE
    // deleted_at), never DELETE — ledger_entries.account_id, budgets.
    // category_id and bills.account_id are RESTRICT composite FKs.
    id: text('id').notNull(),
    userId: uuid('user_id')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    name: text('name').notNull(),
    institution: text('institution'),
    kind: text('kind').notNull(), // system|asset|liability|income|expense
    type: text('type').notNull(),
    status: text('status').notNull(),
    openingBalanceMinor: bigint('opening_balance_minor', { mode: 'number' })
      .notNull()
      .default(0),
    currencyCode: text('currency_code').notNull(),
    colorValue: bigint('color_value', { mode: 'number' }).notNull(),
    iconCode: text('icon_code'),
    notes: text('notes'),
    sortOrder: integer('sort_order').notNull().default(0),
    isHidden: boolean('is_hidden').notNull().default(false),
    version: integer('version').notNull().default(0),
    createdAt: timestamp('created_at', { withTimezone: true }).notNull(),
    updatedAt: timestamp('updated_at', { withTimezone: true }).notNull(),
    deletedAt: timestamp('deleted_at', { withTimezone: true }),
  },
  (t) => [
    primaryKey({ columns: [t.userId, t.id] }),
    index('accounts_user_updated_idx').on(t.userId, t.updatedAt),
  ],
);

export const transactions = pgTable(
  'transactions',
  {
    id: text('id').notNull(),
    userId: uuid('user_id')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    type: text('type').notNull(), // income|expense|transfer
    amountMinor: bigint('amount_minor', { mode: 'number' }).notNull(),
    currencyCode: text('currency_code').notNull(),
    occurredAt: timestamp('occurred_at', { withTimezone: true }).notNull(),
    note: text('note'),
    merchant: text('merchant'),
    referenceNumber: text('reference_number'),
    location: text('location'),
    version: integer('version').notNull().default(0),
    createdAt: timestamp('created_at', { withTimezone: true }).notNull(),
    updatedAt: timestamp('updated_at', { withTimezone: true }).notNull(),
    deletedAt: timestamp('deleted_at', { withTimezone: true }),
  },
  (t) => [
    primaryKey({ columns: [t.userId, t.id] }),
    index('transactions_user_updated_idx').on(t.userId, t.updatedAt),
  ],
);

export const ledgerEntries = pgTable(
  'ledger_entries',
  {
    id: text('id').notNull(),
    userId: uuid('user_id')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    transactionId: text('transaction_id').notNull(),
    accountId: text('account_id').notNull(),
    direction: text('direction').notNull(), // debit|credit
    amountMinor: bigint('amount_minor', { mode: 'number' }).notNull(),
    currencyCode: text('currency_code').notNull(),
  },
  (t) => [
    primaryKey({ columns: [t.userId, t.id] }),
    foreignKey({
      columns: [t.userId, t.transactionId],
      foreignColumns: [transactions.userId, transactions.id],
    }).onDelete('cascade'),
    foreignKey({
      columns: [t.userId, t.accountId],
      foreignColumns: [accounts.userId, accounts.id],
    }),
    index('ledger_entries_transaction_idx').on(t.transactionId),
    index('ledger_entries_account_idx').on(t.accountId),
    index('ledger_entries_user_idx').on(t.userId),
  ],
);

export const tags = pgTable(
  'tags',
  {
    id: text('id').notNull(),
    userId: uuid('user_id')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    name: text('name').notNull(),
    colorValue: bigint('color_value', { mode: 'number' }),
    version: integer('version').notNull().default(0),
    createdAt: timestamp('created_at', { withTimezone: true }).notNull(),
    updatedAt: timestamp('updated_at', { withTimezone: true }).notNull(),
    deletedAt: timestamp('deleted_at', { withTimezone: true }),
  },
  (t) => [
    primaryKey({ columns: [t.userId, t.id] }),
    index('tags_user_updated_idx').on(t.userId, t.updatedAt),
  ],
);

export const transactionTags = pgTable(
  'transaction_tags',
  {
    transactionId: text('transaction_id').notNull(),
    tagId: text('tag_id').notNull(),
    userId: uuid('user_id')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
  },
  (t) => [
    primaryKey({ columns: [t.userId, t.transactionId, t.tagId] }),
    foreignKey({
      columns: [t.userId, t.transactionId],
      foreignColumns: [transactions.userId, transactions.id],
    }).onDelete('cascade'),
    foreignKey({
      columns: [t.userId, t.tagId],
      foreignColumns: [tags.userId, tags.id],
    }).onDelete('cascade'),
    index('transaction_tags_user_idx').on(t.userId),
  ],
);

export const bills = pgTable(
  'bills',
  {
    id: text('id').notNull(),
    userId: uuid('user_id')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    name: text('name').notNull(),
    amountMinor: bigint('amount_minor', { mode: 'number' }).notNull(),
    currencyCode: text('currency_code').notNull(),
    accountId: text('account_id'),
    dueDayOfMonth: integer('due_day_of_month').notNull().default(1),
    reminderDaysBefore: integer('reminder_days_before').notNull().default(3),
    isActive: boolean('is_active').notNull().default(true),
    lastPaidOn: timestamp('last_paid_on', { withTimezone: true }),
    version: integer('version').notNull().default(0),
    createdAt: timestamp('created_at', { withTimezone: true }).notNull(),
    updatedAt: timestamp('updated_at', { withTimezone: true }).notNull(),
    deletedAt: timestamp('deleted_at', { withTimezone: true }),
  },
  (t) => [
    primaryKey({ columns: [t.userId, t.id] }),
    foreignKey({
      columns: [t.userId, t.accountId],
      foreignColumns: [accounts.userId, accounts.id],
    }),
    index('bills_user_updated_idx').on(t.userId, t.updatedAt),
  ],
);

export const budgets = pgTable(
  'budgets',
  {
    id: text('id').notNull(),
    userId: uuid('user_id')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    categoryId: text('category_id').notNull(),
    amountMinor: bigint('amount_minor', { mode: 'number' }).notNull(),
    currencyCode: text('currency_code').notNull(),
    version: integer('version').notNull().default(0),
    createdAt: timestamp('created_at', { withTimezone: true }).notNull(),
    updatedAt: timestamp('updated_at', { withTimezone: true }).notNull(),
    deletedAt: timestamp('deleted_at', { withTimezone: true }),
  },
  (t) => [
    primaryKey({ columns: [t.userId, t.id] }),
    foreignKey({
      columns: [t.userId, t.categoryId],
      foreignColumns: [accounts.userId, accounts.id],
    }),
    index('budgets_user_updated_idx').on(t.userId, t.updatedAt),
  ],
);

export const appSettings = pgTable(
  'app_settings',
  {
    // Key is only unique within a user's scope (device-global keys collide).
    key: text('key').notNull(),
    userId: uuid('user_id')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    value: text('value').notNull(),
    version: integer('version').notNull().default(0),
    updatedAt: timestamp('updated_at', { withTimezone: true }).notNull(),
    deletedAt: timestamp('deleted_at', { withTimezone: true }),
  },
  (t) => [
    primaryKey({ columns: [t.userId, t.key] }),
    index('app_settings_user_updated_idx').on(t.userId, t.updatedAt),
  ],
);

// ---------------------------------------------------------------------------
// Object storage & backups (MinIO blobs referenced, never stored in Postgres)
// ---------------------------------------------------------------------------

export const attachments = pgTable(
  'attachments',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    userId: uuid('user_id')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    transactionId: text('transaction_id'),
    objectKey: text('object_key').notNull(), // MinIO object path
    mimeType: text('mime_type').notNull(),
    sizeBytes: bigint('size_bytes', { mode: 'number' }).notNull(),
    sha256: text('sha256').notNull(),
    // Set by the PATCH confirm once the client reports the presigned PUT done.
    uploadedAt: timestamp('uploaded_at', { withTimezone: true }),
    createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => [
    // CASCADE (NOT SET NULL): Postgres SET NULL on this composite FK would
    // null BOTH columns — including user_id, which is NOT NULL — aborting the
    // users → transactions → attachments cascade chain on user deletion. The
    // orphaned MinIO object is a cleanup job's concern, not a constraint's.
    foreignKey({
      columns: [t.userId, t.transactionId],
      foreignColumns: [transactions.userId, transactions.id],
    }).onDelete('cascade'),
    index('attachments_user_idx').on(t.userId),
  ],
);

export const backups = pgTable(
  'backups',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    userId: uuid('user_id')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    deviceId: uuid('device_id').references(() => devices.id, {
      onDelete: 'set null',
    }),
    objectKey: text('object_key').notNull(), // client-encrypted blob in MinIO
    sizeBytes: bigint('size_bytes', { mode: 'number' }).notNull(),
    sha256: text('sha256').notNull(),
    // Set by the PATCH confirm once the client reports the presigned PUT done.
    uploadedAt: timestamp('uploaded_at', { withTimezone: true }),
    createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => [index('backups_user_idx').on(t.userId)],
);

export type User = typeof users.$inferSelect;
export type Device = typeof devices.$inferSelect;
export type SyncOp = typeof syncOps.$inferSelect;
