import { BadRequestException, Injectable } from '@nestjs/common';
import { and, desc, eq } from 'drizzle-orm';
import { NodePgDatabase } from 'drizzle-orm/node-postgres';
import {
  accounts,
  appSettings,
  bills,
  budgets,
  ledgerEntries,
  syncOps,
  tags,
  transactionTags,
  transactions,
} from '../drizzle/schema';
import { DatabaseService } from '../database/database.service';
import { assertBalancedLedger } from './ledger-validator';

/**
 * A Drizzle database handle that runs queries inside the caller's transaction
 * (both `NodePgDatabase` and Drizzle's transaction client implement this
 * surface; the SyncService casts its transaction client to it).
 */
export type DbClient = NodePgDatabase<typeof import('../drizzle/schema')>;

/**
 * A winning op that must be reflected in the current-state tables.
 * `opId` is the id of the sync_ops row that won LWW for this entity.
 */
export interface MaterializeOp {
  userId: string;
  entity: string;
  entityId: string;
  operation: 'upsert' | 'delete';
  version: number;
  updatedAt: Date;
  deletedAt: Date | null;
  payload: Record<string, unknown> | null;
}

/** Read snapshot of an entity's current state (used for CAS/LWW + conflicts). */
export interface CurrentState {
  version: number;
  updatedAt: Date;
  opId: string;
  /** snake_case payload mirroring what the client pushes (children included). */
  payload: Record<string, unknown> | null;
}

/**
 * Applies winning ops to the current-state mirror tables.
 *
 * Invariants (see docs/BACKEND_API.md §4 + schema comments):
 *  - Accounts are NEVER hard-deleted (RESTRICT FKs from ledger_entries,
 *    budgets and bills) — deletes are `UPDATE deleted_at`.
 *  - A transaction op carries its children (`ledgerEntries`,
 *    `transactionTags`) and is materialized atomically — the header and its
 *    children always change together, inside the caller's transaction.
 *  - Soft-deleting a transaction also removes its ledger entries so derived
 *    balances never include a deleted transaction.
 */
@Injectable()
export class SyncMaterializer {
  constructor(private readonly database: DatabaseService) {}

  /**
   * Materialize one winning op. Must run inside the same DB transaction that
   * appended the op to `sync_ops` (a `NodePgDatabase` transaction client).
   */
  async apply(tx: DbClient, op: MaterializeOp): Promise<void> {
    if (op.operation === 'delete') {
      await this.applyDelete(tx, op);
    } else {
      await this.applyUpsert(tx, op);
    }
  }

  /**
   * Latest known state of an entity for the CAS/LWW check, plus the op id of
   * the op that produced it (for deterministic tie-breaks). Returns `null`
   * when the entity has never been materialized (fresh rows start at version
   * 0 and lose nothing on a LWW compare — version 1 always beats 0).
   */
  /**
   * Reads the current state OUTSIDE a transaction (the push path uses the
   * transaction-scoped variant above). Used by the resources/ write endpoints
   * to learn the version before generating an op.
   */
  async readCurrentPublic(
    userId: string,
    entity: string,
    entityId: string,
  ): Promise<CurrentState | null> {
    return this.readCurrent(this.database.db, userId, entity, entityId);
  }

  async readCurrent(
    tx: DbClient,
    userId: string,
    entity: string,
    entityId: string,
  ): Promise<CurrentState | null> {
    const db = tx;
    switch (entity) {
      case 'account': {
        const [row] = await db
          .select()
          .from(accounts)
          .where(and(eq(accounts.userId, userId), eq(accounts.id, entityId)));
        if (!row) return null;
        const latest = await this.latestOp(db, userId, entity, entityId);
        return {
          version: row.version,
          updatedAt: row.updatedAt,
          opId: latest?.opId ?? '',
          payload: this.accountPayload(row),
        };
      }
      case 'transaction': {
        const [row] = await db
          .select()
          .from(transactions)
          .where(and(eq(transactions.userId, userId), eq(transactions.id, entityId)));
        if (!row) return null;
        const [entries, txnTags] = await Promise.all([
          db
            .select()
            .from(ledgerEntries)
            .where(
              and(
                eq(ledgerEntries.userId, userId),
                eq(ledgerEntries.transactionId, entityId),
              ),
            ),
          db
            .select()
            .from(transactionTags)
            .where(
              and(
                eq(transactionTags.userId, userId),
                eq(transactionTags.transactionId, entityId),
              ),
            ),
        ]);
        const latest = await this.latestOp(db, userId, entity, entityId);
        return {
          version: row.version,
          updatedAt: row.updatedAt,
          opId: latest?.opId ?? '',
          payload: this.transactionPayload(row, entries, txnTags),
        };
      }
      case 'bill': {
        const [row] = await db
          .select()
          .from(bills)
          .where(and(eq(bills.userId, userId), eq(bills.id, entityId)));
        if (!row) return null;
        const latest = await this.latestOp(db, userId, entity, entityId);
        return {
          version: row.version,
          updatedAt: row.updatedAt,
          opId: latest?.opId ?? '',
          payload: this.billPayload(row),
        };
      }
      case 'budget': {
        const [row] = await db
          .select()
          .from(budgets)
          .where(and(eq(budgets.userId, userId), eq(budgets.id, entityId)));
        if (!row) return null;
        const latest = await this.latestOp(db, userId, entity, entityId);
        return {
          version: row.version,
          updatedAt: row.updatedAt,
          opId: latest?.opId ?? '',
          payload: this.budgetPayload(row),
        };
      }
      case 'tag': {
        const [row] = await db
          .select()
          .from(tags)
          .where(and(eq(tags.userId, userId), eq(tags.id, entityId)));
        if (!row) return null;
        const latest = await this.latestOp(db, userId, entity, entityId);
        return {
          version: row.version,
          updatedAt: row.updatedAt,
          opId: latest?.opId ?? '',
          payload: this.tagPayload(row),
        };
      }
      case 'app_setting': {
        const [row] = await db
          .select()
          .from(appSettings)
          .where(
            and(eq(appSettings.userId, userId), eq(appSettings.key, entityId)),
          );
        if (!row) return null;
        const latest = await this.latestOp(db, userId, entity, entityId);
        return {
          version: row.version,
          updatedAt: row.updatedAt,
          opId: latest?.opId ?? '',
          payload: this.appSettingPayload(row),
        };
      }
      default:
        return null;
    }
  }

  // -------------------------------------------------------------------------
  // Upserts
  // -------------------------------------------------------------------------

  private async applyUpsert(tx: DbClient, op: MaterializeOp): Promise<void> {
    const db = tx;
    const p = op.payload ?? {};
    switch (op.entity) {
      case 'account':
        await db
          .insert(accounts)
          .values({
            id: op.entityId,
            userId: op.userId,
            name: this.requiredStr(p, 'name', 'account'),
            institution: this.optStr(p.institution),
            kind: this.requiredStr(p, 'kind', 'account'),
            type: this.requiredStr(p, 'type', 'account'),
            status: this.requiredStr(p, 'status', 'account'),
            openingBalanceMinor: this.int(p.opening_balance_minor, 0),
            currencyCode: this.requiredStr(p, 'currency_code', 'account'),
            colorValue: this.int(p.color_value, 0),
            iconCode: this.optStr(p.icon_code),
            notes: this.optStr(p.notes),
            sortOrder: this.int(p.sort_order, 0),
            isHidden: this.bool(p.is_hidden, false),
            version: op.version,
            createdAt: this.date(p.created_at, op.updatedAt),
            updatedAt: op.updatedAt,
            deletedAt: null,
          })
          .onConflictDoUpdate({
            target: [accounts.userId, accounts.id],
            set: {
              name: this.requiredStr(p, 'name', 'account'),
              institution: this.optStr(p.institution),
              kind: this.requiredStr(p, 'kind', 'account'),
              type: this.requiredStr(p, 'type', 'account'),
              status: this.requiredStr(p, 'status', 'account'),
              openingBalanceMinor: this.int(p.opening_balance_minor, 0),
              currencyCode: this.requiredStr(p, 'currency_code', 'account'),
              colorValue: this.int(p.color_value, 0),
              iconCode: this.optStr(p.icon_code),
              notes: this.optStr(p.notes),
              sortOrder: this.int(p.sort_order, 0),
              isHidden: this.bool(p.is_hidden, false),
              version: op.version,
              updatedAt: op.updatedAt,
              deletedAt: null, // an upsert revives a soft-deleted row
            },
          });
        return;

      case 'transaction': {
        // Never store an unbalanced ledger (same invariant as the Dart engine).
        assertBalancedLedger(p);
        const entries = this.ledgerEntriesFrom(p, op.entityId, op.userId);
        const tagIds = this.transactionTagIds(p);
        await db
          .insert(transactions)
          .values({
            id: op.entityId,
            userId: op.userId,
            type: this.requiredStr(p, 'type', 'transaction'),
            amountMinor: this.positiveInt(p.amount_minor, 'transaction'),
            currencyCode: this.requiredStr(p, 'currency_code', 'transaction'),
            occurredAt: this.date(p.occurred_at, op.updatedAt),
            note: this.optStr(p.note),
            merchant: this.optStr(p.merchant),
            referenceNumber: this.optStr(p.reference_number),
            location: this.optStr(p.location),
            version: op.version,
            createdAt: this.date(p.created_at, op.updatedAt),
            updatedAt: op.updatedAt,
            deletedAt: null,
          })
          .onConflictDoUpdate({
            target: [transactions.userId, transactions.id],
            set: {
              type: this.requiredStr(p, 'type', 'transaction'),
              amountMinor: this.positiveInt(p.amount_minor, 'transaction'),
              currencyCode: this.requiredStr(p, 'currency_code', 'transaction'),
              occurredAt: this.date(p.occurred_at, op.updatedAt),
              note: this.optStr(p.note),
              merchant: this.optStr(p.merchant),
              referenceNumber: this.optStr(p.reference_number),
              location: this.optStr(p.location),
              version: op.version,
              updatedAt: op.updatedAt,
              deletedAt: null,
            },
          });
        // Children are replaced as a consistent set (never half-applied).
        await db
          .delete(ledgerEntries)
          .where(
            and(
              eq(ledgerEntries.userId, op.userId),
              eq(ledgerEntries.transactionId, op.entityId),
            ),
          );
        await db
          .delete(transactionTags)
          .where(
            and(
              eq(transactionTags.userId, op.userId),
              eq(transactionTags.transactionId, op.entityId),
            ),
          );
        if (entries.length > 0) {
          await db.insert(ledgerEntries).values(entries);
        }
        if (tagIds.length > 0) {
          await db
            .insert(transactionTags)
            .values(
              tagIds.map((tagId) => ({
                transactionId: op.entityId,
                tagId,
                userId: op.userId,
              })),
            );
        }
        return;
      }

      case 'bill':
        await db
          .insert(bills)
          .values({
            id: op.entityId,
            userId: op.userId,
            name: this.requiredStr(p, 'name', 'bill'),
            amountMinor: this.positiveInt(p.amount_minor, 'bill'),
            currencyCode: this.requiredStr(p, 'currency_code', 'bill'),
            accountId: this.optStr(p.account_id),
            dueDayOfMonth: this.int(p.due_day_of_month, 1),
            reminderDaysBefore: this.int(p.reminder_days_before, 3),
            isActive: this.bool(p.is_active, true),
            lastPaidOn: this.optDate(p.last_paid_on),
            version: op.version,
            createdAt: this.date(p.created_at, op.updatedAt),
            updatedAt: op.updatedAt,
            deletedAt: null,
          })
          .onConflictDoUpdate({
            target: [bills.userId, bills.id],
            set: {
              name: this.requiredStr(p, 'name', 'bill'),
              amountMinor: this.positiveInt(p.amount_minor, 'bill'),
              currencyCode: this.requiredStr(p, 'currency_code', 'bill'),
              accountId: this.optStr(p.account_id),
              dueDayOfMonth: this.int(p.due_day_of_month, 1),
              reminderDaysBefore: this.int(p.reminder_days_before, 3),
              isActive: this.bool(p.is_active, true),
              lastPaidOn: this.optDate(p.last_paid_on),
              version: op.version,
              updatedAt: op.updatedAt,
              deletedAt: null,
            },
          });
        return;

      case 'budget':
        await db
          .insert(budgets)
          .values({
            id: op.entityId,
            userId: op.userId,
            categoryId: this.requiredStr(p, 'category_id', 'budget'),
            amountMinor: this.positiveInt(p.amount_minor, 'budget'),
            currencyCode: this.requiredStr(p, 'currency_code', 'budget'),
            version: op.version,
            createdAt: this.date(p.created_at, op.updatedAt),
            updatedAt: op.updatedAt,
            deletedAt: null,
          })
          .onConflictDoUpdate({
            target: [budgets.userId, budgets.id],
            set: {
              categoryId: this.requiredStr(p, 'category_id', 'budget'),
              amountMinor: this.positiveInt(p.amount_minor, 'budget'),
              currencyCode: this.requiredStr(p, 'currency_code', 'budget'),
              version: op.version,
              updatedAt: op.updatedAt,
              deletedAt: null,
            },
          });
        return;

      case 'tag':
        await db
          .insert(tags)
          .values({
            id: op.entityId,
            userId: op.userId,
            name: this.requiredStr(p, 'name', 'tag'),
            colorValue: this.optInt(p.color_value),
            version: op.version,
            createdAt: this.date(p.created_at, op.updatedAt),
            updatedAt: op.updatedAt,
            deletedAt: null,
          })
          .onConflictDoUpdate({
            target: [tags.userId, tags.id],
            set: {
              name: this.requiredStr(p, 'name', 'tag'),
              colorValue: this.optInt(p.color_value),
              version: op.version,
              updatedAt: op.updatedAt,
              deletedAt: null,
            },
          });
        return;

      case 'app_setting':
        await db
          .insert(appSettings)
          .values({
            key: op.entityId,
            userId: op.userId,
            value: this.requiredStr(p, 'value', 'app_setting'),
            version: op.version,
            updatedAt: op.updatedAt,
            deletedAt: null,
          })
          .onConflictDoUpdate({
            target: [appSettings.userId, appSettings.key],
            set: {
              value: this.requiredStr(p, 'value', 'app_setting'),
              version: op.version,
              updatedAt: op.updatedAt,
              deletedAt: null,
            },
          });
        return;

      default:
        throw new BadRequestException(`Unknown sync entity: ${op.entity}`);
    }
  }

  // -------------------------------------------------------------------------
  // Soft deletes
  // -------------------------------------------------------------------------

  private async applyDelete(tx: DbClient, op: MaterializeOp): Promise<void> {
    const db = tx;
    const deletedAt = op.deletedAt ?? new Date();
    switch (op.entity) {
      case 'account':
        await db
          .update(accounts)
          .set({ deletedAt, version: op.version, updatedAt: op.updatedAt })
          .where(and(eq(accounts.userId, op.userId), eq(accounts.id, op.entityId)));
        return;
      case 'transaction':
        await db
          .update(transactions)
          .set({ deletedAt, version: op.version, updatedAt: op.updatedAt })
          .where(
            and(eq(transactions.userId, op.userId), eq(transactions.id, op.entityId)),
          );
        // Derived balances must never include a deleted transaction.
        await db
          .delete(ledgerEntries)
          .where(
            and(
              eq(ledgerEntries.userId, op.userId),
              eq(ledgerEntries.transactionId, op.entityId),
            ),
          );
        await db
          .delete(transactionTags)
          .where(
            and(
              eq(transactionTags.userId, op.userId),
              eq(transactionTags.transactionId, op.entityId),
            ),
          );
        return;
      case 'bill':
        await db
          .update(bills)
          .set({ deletedAt, version: op.version, updatedAt: op.updatedAt })
          .where(and(eq(bills.userId, op.userId), eq(bills.id, op.entityId)));
        return;
      case 'budget':
        await db
          .update(budgets)
          .set({ deletedAt, version: op.version, updatedAt: op.updatedAt })
          .where(and(eq(budgets.userId, op.userId), eq(budgets.id, op.entityId)));
        return;
      case 'tag':
        await db
          .update(tags)
          .set({ deletedAt, version: op.version, updatedAt: op.updatedAt })
          .where(and(eq(tags.userId, op.userId), eq(tags.id, op.entityId)));
        return;
      case 'app_setting':
        await db
          .update(appSettings)
          .set({ deletedAt, version: op.version, updatedAt: op.updatedAt })
          .where(
            and(
              eq(appSettings.userId, op.userId),
              eq(appSettings.key, op.entityId),
            ),
          );
        return;
      default:
        throw new BadRequestException(`Unknown sync entity: ${op.entity}`);
    }
  }

  // -------------------------------------------------------------------------
  // Current-state → wire payloads (snake_case, matching the push shape)
  // -------------------------------------------------------------------------

  private async latestOp(
    db: DbClient,
    userId: string,
    entity: string,
    entityId: string,
  ) {
    const [row] = await db
      .select({ opId: syncOps.opId, seq: syncOps.seq })
      .from(syncOps)
      .where(
        and(
          eq(syncOps.userId, userId),
          eq(syncOps.entity, entity),
          eq(syncOps.entityId, entityId),
        ),
      )
      .orderBy(desc(syncOps.seq))
      .limit(1);
    return row ?? null;
  }

  /** Public payload converters — reused by the read endpoints (resources/). */
  accountPayload(row: typeof accounts.$inferSelect): Record<string, unknown> {
    return {
      id: row.id,
      name: row.name,
      institution: row.institution,
      kind: row.kind,
      type: row.type,
      status: row.status,
      opening_balance_minor: row.openingBalanceMinor,
      currency_code: row.currencyCode,
      color_value: row.colorValue,
      icon_code: row.iconCode,
      notes: row.notes,
      sort_order: row.sortOrder,
      is_hidden: row.isHidden,
      version: row.version,
      created_at: row.createdAt.toISOString(),
      updated_at: row.updatedAt.toISOString(),
      deleted_at: row.deletedAt?.toISOString() ?? null,
    };
  }

  transactionPayload(
    row: typeof transactions.$inferSelect,
    entries: (typeof ledgerEntries.$inferSelect)[],
    txnTags: (typeof transactionTags.$inferSelect)[],
  ): Record<string, unknown> {
    return {
      id: row.id,
      type: row.type,
      amount_minor: row.amountMinor,
      currency_code: row.currencyCode,
      occurred_at: row.occurredAt.toISOString(),
      note: row.note,
      merchant: row.merchant,
      reference_number: row.referenceNumber,
      location: row.location,
      version: row.version,
      created_at: row.createdAt.toISOString(),
      updated_at: row.updatedAt.toISOString(),
      deleted_at: row.deletedAt?.toISOString() ?? null,
      ledgerEntries: entries.map((e) => ({
        id: e.id,
        account_id: e.accountId,
        direction: e.direction,
        amount_minor: e.amountMinor,
        currency_code: e.currencyCode,
      })),
      transactionTags: txnTags.map((t) => ({ tag_id: t.tagId })),
    };
  }

  billPayload(row: typeof bills.$inferSelect): Record<string, unknown> {
    return {
      id: row.id,
      name: row.name,
      amount_minor: row.amountMinor,
      currency_code: row.currencyCode,
      account_id: row.accountId,
      due_day_of_month: row.dueDayOfMonth,
      reminder_days_before: row.reminderDaysBefore,
      is_active: row.isActive,
      last_paid_on: row.lastPaidOn?.toISOString() ?? null,
      version: row.version,
      created_at: row.createdAt.toISOString(),
      updated_at: row.updatedAt.toISOString(),
      deleted_at: row.deletedAt?.toISOString() ?? null,
    };
  }

  budgetPayload(row: typeof budgets.$inferSelect): Record<string, unknown> {
    return {
      id: row.id,
      category_id: row.categoryId,
      amount_minor: row.amountMinor,
      currency_code: row.currencyCode,
      version: row.version,
      created_at: row.createdAt.toISOString(),
      updated_at: row.updatedAt.toISOString(),
      deleted_at: row.deletedAt?.toISOString() ?? null,
    };
  }

  tagPayload(row: typeof tags.$inferSelect): Record<string, unknown> {
    return {
      id: row.id,
      name: row.name,
      color_value: row.colorValue,
      version: row.version,
      created_at: row.createdAt.toISOString(),
      updated_at: row.updatedAt.toISOString(),
      deleted_at: row.deletedAt?.toISOString() ?? null,
    };
  }

  appSettingPayload(
    row: typeof appSettings.$inferSelect,
  ): Record<string, unknown> {
    return {
      key: row.key,
      value: row.value,
      version: row.version,
      updated_at: row.updatedAt.toISOString(),
      deleted_at: row.deletedAt?.toISOString() ?? null,
    };
  }

  // -------------------------------------------------------------------------
  // Payload helpers
  // -------------------------------------------------------------------------

  private requiredStr(
    p: Record<string, unknown>,
    key: string,
    entity: string,
  ): string {
    const v = p[key];
    if (typeof v !== 'string' || v.length === 0) {
      throw new BadRequestException(
        `Malformed ${entity} payload: "${key}" must be a non-empty string`,
      );
    }
    return v;
  }

  private optStr(v: unknown): string | null {
    return typeof v === 'string' && v.length > 0 ? v : null;
  }

  /**
   * Monetary amounts are integers in minor units, stored as bigints. JSON
   * numbers above 2^53 silently lose precision in JSON.parse, so anything
   * beyond the safe range is rejected rather than silently truncated.
   */
  private static readonly MAX_SAFE_MONEY = Number.MAX_SAFE_INTEGER;

  /**
   * Strict integer coercion: absent → fallback, present-but-invalid → 400.
   * Money/amount fields must NEVER be silently coerced (a web client that
   * serialises a large Dart int as a JSON string would otherwise have its
   * opening balance silently written as 0 — silent data corruption).
   */
  private int(v: unknown, fallback: number): number {
    if (v === undefined || v === null) return fallback;
    if (
      typeof v === 'number' &&
      Number.isInteger(v) &&
      v <= SyncMaterializer.MAX_SAFE_MONEY
    ) {
      return v;
    }
    throw new BadRequestException(
      'Malformed payload: integer field must be a safe integer (received a string or non-integer)',
    );
  }

  private optInt(v: unknown): number | null {
    if (v === undefined || v === null) return null;
    if (
      typeof v === 'number' &&
      Number.isInteger(v) &&
      v <= SyncMaterializer.MAX_SAFE_MONEY
    ) {
      return v;
    }
    throw new BadRequestException(
      'Malformed payload: integer field must be a safe integer (received a string or non-integer)',
    );
  }

  private positiveInt(v: unknown, entity: string): number {
    if (
      typeof v !== 'number' ||
      !Number.isInteger(v) ||
      v <= 0 ||
      v > SyncMaterializer.MAX_SAFE_MONEY
    ) {
      throw new BadRequestException(
        `Malformed ${entity} payload: amount_minor must be a positive safe integer`,
      );
    }
    return v;
  }

  private bool(v: unknown, fallback: boolean): boolean {
    if (v === undefined || v === null) return fallback;
    if (typeof v === 'boolean') return v;
    throw new BadRequestException(
      'Malformed payload: boolean field must be a boolean',
    );
  }

  private date(v: unknown, fallback: Date): Date {
    const d = this.optDate(v);
    return d ?? fallback;
  }

  private optDate(v: unknown): Date | null {
    if (v instanceof Date) return v;
    if (typeof v === 'string' && v.length > 0) {
      const d = new Date(v);
      if (!Number.isNaN(d.getTime())) return d;
    }
    return null;
  }

  private ledgerEntriesFrom(
    p: Record<string, unknown>,
    transactionId: string,
    userId: string,
  ): (typeof ledgerEntries.$inferInsert)[] {
    const raw = p['ledgerEntries'];
    if (!Array.isArray(raw)) return [];
    const seenIds = new Set<string>();
    return raw.map((entry, i) => {
      if (typeof entry !== 'object' || entry === null) {
        throw new BadRequestException(
          `Malformed transaction payload: ledgerEntries[${i}] must be an object`,
        );
      }
      const e = entry as Record<string, unknown>;
      const accountId = this.optStr(e.account_id);
      const direction = e.direction;
      if (!accountId) {
        throw new BadRequestException(
          `Malformed transaction payload: ledgerEntries[${i}].account_id is required`,
        );
      }
      if (direction !== 'debit' && direction !== 'credit') {
        throw new BadRequestException(
          `Malformed transaction payload: ledgerEntries[${i}].direction must be debit or credit`,
        );
      }
      const amountMinor = this.positiveInt(e.amount_minor, 'ledger entry');
      const currencyCode = this.optStr(e.currency_code);
      if (!currencyCode) {
        throw new BadRequestException(
          `Malformed transaction payload: ledgerEntries[${i}].currency_code is required`,
        );
      }
      // Entry ids must be unique within the transaction (the (user, id) PK
      // would otherwise collide → 500). Generate one when absent/duplicate —
      // the generated fallback must itself be checked against explicit ids
      // already seen (a client could legitimately choose `<txnId>-0`).
      let id = this.optStr(e.id);
      if (!id || seenIds.has(id)) {
        let suffix = i;
        do {
          id = `${transactionId}-${suffix}`;
          suffix += 1;
        } while (seenIds.has(id));
      }
      seenIds.add(id);
      return {
        id,
        userId,
        transactionId,
        accountId,
        direction,
        amountMinor,
        currencyCode,
      };
    });
  }

  private transactionTagIds(p: Record<string, unknown>): string[] {
    const raw = p['transactionTags'];
    if (!Array.isArray(raw)) return [];
    // Dedupe: the (user, transaction, tag) PK would otherwise collide (23505 →
    // 500) when a payload lists the same tag twice.
    const seen = new Set<string>();
    const ids: string[] = [];
    for (const item of raw) {
      const tagId =
        typeof item === 'string' && item.length > 0
          ? item
          : typeof item === 'object' && item !== null
            ? this.optStr((item as Record<string, unknown>).tag_id)
            : null;
      if (tagId && !seen.has(tagId)) {
        seen.add(tagId);
        ids.push(tagId);
      }
    }
    return ids;
  }
}
