import {
  BadRequestException,
  ConflictException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { and, count, desc, eq, isNull } from 'drizzle-orm';
import { randomUUID } from 'node:crypto';
import { CurrentUser } from '../auth/current-user.interface';
import { DatabaseService } from '../database/database.service';
import {
  accounts,
  appSettings,
  bills,
  budgets,
  ledgerEntries,
  tags,
  transactionTags,
  transactions,
} from '../drizzle/schema';
import { SyncMaterializer } from '../sync/sync-materializer.service';
import { SyncService } from '../sync/sync.service';

/** Entities served by the read endpoints (docs/BACKEND_API.md §5). */
export type ResourceEntity =
  | 'account'
  | 'transaction'
  | 'bill'
  | 'budget'
  | 'tag'
  | 'app_setting';

/** App-settings keys that must never be served or written via the API. */
const FORBIDDEN_SETTING_PREFIXES = ['security.', 'pin.'];

@Injectable()
export class ResourcesService {
  constructor(
    private readonly database: DatabaseService,
    private readonly materializer: SyncMaterializer,
    private readonly sync: SyncService,
  ) {}

  // -------------------------------------------------------------------------
  // Reads
  // -------------------------------------------------------------------------

  async list(userId: string, entity: ResourceEntity, page = 1, limit = 50) {
    const offset = (page - 1) * limit;
    const db = this.database.db;

    let rows: Record<string, unknown>[] = [];
    let total = 0;

    switch (entity) {
      case 'account': {
        const [t] = await db
          .select({ n: count() })
          .from(accounts)
          .where(and(eq(accounts.userId, userId), isNull(accounts.deletedAt)));
        total = t?.n ?? 0;
        const found = await db
          .select()
          .from(accounts)
          .where(and(eq(accounts.userId, userId), isNull(accounts.deletedAt)))
          .orderBy(desc(accounts.updatedAt))
          .limit(limit)
          .offset(offset);
        rows = found.map((r) => this.materializer.accountPayload(r));
        break;
      }
      case 'transaction': {
        const [t] = await db
          .select({ n: count() })
          .from(transactions)
          .where(and(eq(transactions.userId, userId), isNull(transactions.deletedAt)));
        total = t?.n ?? 0;
        const found = await db
          .select()
          .from(transactions)
          .where(and(eq(transactions.userId, userId), isNull(transactions.deletedAt)))
          .orderBy(desc(transactions.occurredAt))
          .limit(limit)
          .offset(offset);
        rows = found.map((r) => this.transactionHeader(r));
        break;
      }
      case 'bill': {
        const [t] = await db
          .select({ n: count() })
          .from(bills)
          .where(and(eq(bills.userId, userId), isNull(bills.deletedAt)));
        total = t?.n ?? 0;
        const found = await db
          .select()
          .from(bills)
          .where(and(eq(bills.userId, userId), isNull(bills.deletedAt)))
          .orderBy(desc(bills.updatedAt))
          .limit(limit)
          .offset(offset);
        rows = found.map((r) => this.materializer.billPayload(r));
        break;
      }
      case 'budget': {
        const [t] = await db
          .select({ n: count() })
          .from(budgets)
          .where(and(eq(budgets.userId, userId), isNull(budgets.deletedAt)));
        total = t?.n ?? 0;
        const found = await db
          .select()
          .from(budgets)
          .where(and(eq(budgets.userId, userId), isNull(budgets.deletedAt)))
          .orderBy(desc(budgets.updatedAt))
          .limit(limit)
          .offset(offset);
        rows = found.map((r) => this.materializer.budgetPayload(r));
        break;
      }
      case 'tag': {
        const [t] = await db
          .select({ n: count() })
          .from(tags)
          .where(and(eq(tags.userId, userId), isNull(tags.deletedAt)));
        total = t?.n ?? 0;
        const found = await db
          .select()
          .from(tags)
          .where(and(eq(tags.userId, userId), isNull(tags.deletedAt)))
          .orderBy(desc(tags.updatedAt))
          .limit(limit)
          .offset(offset);
        rows = found.map((r) => this.materializer.tagPayload(r));
        break;
      }
      case 'app_setting': {
        const [t] = await db
          .select({ n: count() })
          .from(appSettings)
          .where(and(eq(appSettings.userId, userId), isNull(appSettings.deletedAt)));
        total = t?.n ?? 0;
        const found = await db
          .select()
          .from(appSettings)
          .where(and(eq(appSettings.userId, userId), isNull(appSettings.deletedAt)))
          .orderBy(desc(appSettings.updatedAt))
          .limit(limit)
          .offset(offset);
        rows = found
          .filter((r) => !isForbiddenSetting(r.key))
          .map((r) => this.materializer.appSettingPayload(r));
        break;
      }
      default:
        throw new BadRequestException(`Unknown resource: ${entity}`);
    }

    return { items: rows, page, limit, total, hasMore: offset + rows.length < total };
  }

  async get(userId: string, entity: ResourceEntity, id: string) {
    const db = this.database.db;
    switch (entity) {
      case 'account': {
        const [row] = await db
          .select()
          .from(accounts)
          .where(and(eq(accounts.userId, userId), eq(accounts.id, id), isNull(accounts.deletedAt)));
        if (!row) throw new NotFoundException('Account not found');
        return this.materializer.accountPayload(row);
      }
      case 'transaction': {
        const [row] = await db
          .select()
          .from(transactions)
          .where(
            and(
              eq(transactions.userId, userId),
              eq(transactions.id, id),
              isNull(transactions.deletedAt),
            ),
          );
        if (!row) throw new NotFoundException('Transaction not found');
        const [entries, txnTags] = await Promise.all([
          db
            .select()
            .from(ledgerEntries)
            .where(
              and(
                eq(ledgerEntries.userId, userId),
                eq(ledgerEntries.transactionId, id),
              ),
            ),
          db
            .select()
            .from(transactionTags)
            .where(
              and(
                eq(transactionTags.userId, userId),
                eq(transactionTags.transactionId, id),
              ),
            ),
        ]);
        return this.materializer.transactionPayload(row, entries, txnTags);
      }
      case 'bill': {
        const [row] = await db
          .select()
          .from(bills)
          .where(and(eq(bills.userId, userId), eq(bills.id, id), isNull(bills.deletedAt)));
        if (!row) throw new NotFoundException('Bill not found');
        return this.materializer.billPayload(row);
      }
      case 'budget': {
        const [row] = await db
          .select()
          .from(budgets)
          .where(and(eq(budgets.userId, userId), eq(budgets.id, id), isNull(budgets.deletedAt)));
        if (!row) throw new NotFoundException('Budget not found');
        return this.materializer.budgetPayload(row);
      }
      case 'tag': {
        const [row] = await db
          .select()
          .from(tags)
          .where(and(eq(tags.userId, userId), eq(tags.id, id), isNull(tags.deletedAt)));
        if (!row) throw new NotFoundException('Tag not found');
        return this.materializer.tagPayload(row);
      }
      case 'app_setting': {
        if (isForbiddenSetting(id)) throw new NotFoundException('Setting not found');
        const [row] = await db
          .select()
          .from(appSettings)
          .where(
            and(eq(appSettings.userId, userId), eq(appSettings.key, id), isNull(appSettings.deletedAt)),
          );
        if (!row) throw new NotFoundException('Setting not found');
        return this.materializer.appSettingPayload(row);
      }
      default:
        throw new BadRequestException(`Unknown resource: ${entity}`);
    }
  }

  // -------------------------------------------------------------------------
  // Writes — every write generates an op through the sync engine so the
  // current-state mirror and the op log stay consistent (single write path).
  // -------------------------------------------------------------------------

  async create(
    user: CurrentUser,
    entity: ResourceEntity,
    payload: Record<string, unknown>,
    entityId?: string,
  ): Promise<Record<string, unknown>> {
    const id = entityId ?? (typeof payload['id'] === 'string' ? payload['id'] : randomUUID());
    if (entity === 'app_setting' && isForbiddenSetting(id)) {
      throw new BadRequestException('security.* settings cannot be written via the API');
    }
    const op = this.buildOp(entity, id, 'upsert', 0, 1, payload, user.deviceId);
    return (await this.pushSingle(user, op))!;
  }

  async update(
    user: CurrentUser,
    entity: ResourceEntity,
    entityId: string,
    payload: Record<string, unknown>,
  ): Promise<Record<string, unknown>> {
    if (entity === 'app_setting' && isForbiddenSetting(entityId)) {
      throw new BadRequestException('security.* settings cannot be written via the API');
    }
    const current = await this.materializer.readCurrentPublic(user.userId, entity, entityId);
    const baseVersion = current?.version ?? 0;
    const op = this.buildOp(
      entity,
      entityId,
      'upsert',
      baseVersion,
      baseVersion + 1,
      payload,
      user.deviceId,
    );
    return (await this.pushSingle(user, op))!;
  }

  async remove(user: CurrentUser, entity: ResourceEntity, entityId: string) {
    if (entity === 'app_setting' && isForbiddenSetting(entityId)) {
      throw new BadRequestException('security.* settings cannot be written via the API');
    }
    const current = await this.materializer.readCurrentPublic(user.userId, entity, entityId);
    if (!current) throw new NotFoundException('Resource not found');
    const op = this.buildOp(
      entity,
      entityId,
      'delete',
      current.version,
      current.version + 1,
      null,
      user.deviceId,
    );
    await this.pushSingle(user, op);
    return undefined;
  }

  /**
   * Pushes a single op; surfaces conflicts as a 409 with the current state.
   * For upserts the freshly-materialised row is returned; deletes return
   * undefined (the row no longer exists in reads).
   */
  private async pushSingle(user: CurrentUser, op: Record<string, unknown>) {
    const res = await this.sync.push(user, { ops: [op as never] });
    if (res.conflicts.length > 0) {
      throw new ConflictException({
        code: 'CONFLICT',
        message: 'Resource was modified concurrently — re-fetch and retry',
        current: res.conflicts[0].current,
      });
    }
    if (op['operation'] === 'delete') {
      return undefined;
    }
    const entity = op['entity'] as ResourceEntity;
    const entityId = op['entityId'] as string;
    return this.get(user.userId, entity, entityId);
  }

  private buildOp(
    entity: ResourceEntity,
    entityId: string,
    operation: 'upsert' | 'delete',
    baseVersion: number,
    version: number,
    payload: Record<string, unknown> | null,
    deviceId: string,
  ): Record<string, unknown> {
    return {
      opId: randomUUID(),
      deviceId,
      entity,
      entityId,
      operation,
      baseVersion,
      version,
      payload,
      updatedAt: new Date().toISOString(),
      deletedAt: operation === 'delete' ? new Date().toISOString() : null,
    };
  }

  private transactionHeader(row: typeof transactions.$inferSelect): Record<string, unknown> {
    const { ledgerEntries: _e, transactionTags: _t, ...rest } = this.materializer.transactionPayload(
      row,
      [],
      [],
    );
    return rest;
  }
}

function isForbiddenSetting(key: string): boolean {
  return FORBIDDEN_SETTING_PREFIXES.some((prefix) => key.startsWith(prefix));
}
