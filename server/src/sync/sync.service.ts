import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { and, asc, eq, gt } from 'drizzle-orm';
import { sql } from 'drizzle-orm';
import { CurrentUser } from '../auth/current-user.interface';
import { DatabaseService } from '../database/database.service';
import { devices, syncOps } from '../drizzle/schema';
import { assertBalancedLedger } from './ledger-validator';
import { lwwWinner } from './lww';
import {
  CurrentState,
  DbClient,
  MaterializeOp,
  SyncMaterializer,
} from './sync-materializer.service';
import { MAX_PULL_PAGE, PushDto, SyncOpDto } from './sync-op.dto';

/** Max serialized size of a single op payload (the 2mb body cap bounds batches). */
const MAX_PAYLOAD_BYTES = 100 * 1024;

/**
 * Is this a Postgres error with the given SQLSTATE code? Drizzle wraps pg
 * errors in DrizzleQueryError with the pg error at `.cause` (single level —
 * if another wrapper is ever added, the remap below silently stops matching).
 */
function isPgError(error: unknown, code: string): boolean {
  const cause = (error as { cause?: { code?: unknown } })?.cause;
  return cause?.code === code;
}

/**
 * The operation-log sync engine (docs/BACKEND_API.md §4).
 *
 * Push (one DB transaction, ops processed sequentially):
 *   0. A per-(user, entity, entityId) Postgres **advisory transaction lock**
 *      serialises concurrent pushes — two devices can never both pass the CAS
 *      check for the same entity. (Advisory locks also cover fresh rows, which
 *      a `SELECT … FOR UPDATE` on the current-state table cannot — there is no
 *      row to lock yet.)
 *   1. Idempotent by `op_id` — a replayed op returns its original `seq`.
 *   2. CAS: `base_version > stored version` → conflict (client re-bases).
 *   3. Stale (LWW says the stored state wins) → conflict too: the client MUST
 *      see the winner (via pull) and re-base, otherwise its cursor would jump
 *      past the winning op and the two devices would silently diverge. The
 *      conflict carries `current` so the client can re-base immediately.
 *   4. Winner → appended to `sync_ops` + materialised into the current-state
 *      tables (children atomically for transactions).
 *
 * Pull: repeatable, immutable — `seq` is server-assigned and never changes, so
 * the same cursor always returns the same ops. Ops are returned parent-first
 * (accounts/tags/settings → bills/budgets → transactions) so a fresh client
 * can apply them into its local FK-enforcing database without buffering.
 */
@Injectable()
export class SyncService {
  constructor(
    private readonly database: DatabaseService,
    private readonly materializer: SyncMaterializer,
  ) {}

  /** Parent-first application order (FK-safe on the client's local DB). */
  private static readonly ENTITY_PRIORITY: Record<string, number> = {
    account: 0,
    tag: 0,
    app_setting: 0,
    bill: 1,
    budget: 1,
    transaction: 2,
  };

  async push(user: CurrentUser, dto: PushDto): Promise<{
    applied: { opId: string; seq: number }[];
    conflicts: { opId: string; current: Record<string, unknown> | null }[];
    serverCursor: number | null;
  }> {
    // The envelope carries deviceId per spec, but the token is the authority.
    for (const op of dto.ops) {
      if (op.deviceId !== user.deviceId) {
        throw new ForbiddenException(
          'Operation deviceId does not match the access token',
        );
      }
    }
    await this.assertDeviceActive(user.userId, user.deviceId);

    // ---- Fail fast BEFORE the transaction (nothing is ever half-applied) ----
    for (const op of dto.ops) {
      const size = JSON.stringify(op.payload ?? {}).length;
      if (size > MAX_PAYLOAD_BYTES) {
        throw new BadRequestException(
          `Operation payload exceeds the ${MAX_PAYLOAD_BYTES} byte limit`,
        );
      }
      // Validate the double-entry invariant before touching the log so a bad
      // batch rolls back nothing: the whole batch fails fast with 409.
      if (op.entity === 'transaction' && op.operation === 'upsert') {
        assertBalancedLedger(op.payload ?? {});
      }
    }

    // Parent-first (FK-safe) AND deterministic: the (priority, entityId) order
    // guarantees advisory locks are always acquired in the same sequence, so
    // two concurrent pushes of the same entities can never deadlock (AB-BA).
    const ordered = [...dto.ops].sort((a, b) => {
      const byPriority =
        (SyncService.ENTITY_PRIORITY[a.entity] ?? 0) -
        (SyncService.ENTITY_PRIORITY[b.entity] ?? 0);
      return byPriority !== 0
        ? byPriority
        : a.entityId.localeCompare(b.entityId);
    });

    const applied: { opId: string; seq: number }[] = [];
    const conflicts: {
      opId: string;
      current: Record<string, unknown> | null;
    }[] = [];

    const db = this.database.db;
    try {
      await db.transaction(async (tx) => {
        // Re-check the device ATOMICALLY with the writes: the row is locked
        // (FOR UPDATE) for the whole transaction, so a device revoked mid-push
        // can no longer interleave — either the push commits, or the revoke
        // lands first and the push aborts with 403 before writing anything.
        const [device] = await tx
          .select({ revokedAt: devices.revokedAt })
          .from(devices)
          .where(and(eq(devices.id, user.deviceId), eq(devices.userId, user.userId)))
          .for('update');
        if (!device) {
          throw new NotFoundException('Device not found');
        }
        if (device.revokedAt) {
          throw new ForbiddenException('Device has been revoked');
        }

        for (const op of ordered) {
          // 0. Serialise writers on this entity for the whole transaction.
          const lockKey = `${user.userId}:${op.entity}:${op.entityId}`;
          await tx.execute(
            sql`SELECT pg_advisory_xact_lock(hashtextextended(${lockKey}, 0))`,
          );

          // 1. Idempotency — an opId already in the log is a replay of the
          //    SAME op: skipped, original seq returned. An opId targeting a
          //    DIFFERENT entity is a client bug (idempotency keys must be
          //    unique per logical op) — a silent ack would leave the second
          //    entity permanently unmaterialised.
          const [existing] = await tx
            .select()
            .from(syncOps)
            .where(eq(syncOps.opId, op.opId));
          if (existing) {
            if (
              existing.entity !== op.entity ||
              existing.entityId !== op.entityId ||
              existing.operation !== op.operation
            ) {
              throw new ConflictException(
                'opId was already used for a different operation — idempotency keys must be unique per logical op',
              );
            }
            applied.push({ opId: op.opId, seq: existing.seq });
            continue;
          }

          // 2+3. CAS + LWW against the current state.
          const current = await this.materializer.readCurrent(
            tx as unknown as DbClient,
            user.userId,
            op.entity,
            op.entityId,
          );
          if (this.rejects(current, op)) {
            conflicts.push({
              opId: op.opId,
              current: current?.payload ?? null,
            });
            continue;
          }

          // 4. Append + materialise atomically.
          const [inserted] = await tx
            .insert(syncOps)
            .values({
              opId: op.opId,
              userId: user.userId,
              deviceId: user.deviceId,
              entity: op.entity,
              entityId: op.entityId,
              operation: op.operation,
              baseVersion: op.baseVersion,
              version: op.version,
              payload: op.payload,
              updatedAt: new Date(op.updatedAt),
              deletedAt: op.deletedAt ? new Date(op.deletedAt) : null,
            })
            .returning({ seq: syncOps.seq });

          const materialize: MaterializeOp = {
            userId: user.userId,
            entity: op.entity,
            entityId: op.entityId,
            operation: op.operation as MaterializeOp['operation'],
            version: op.version,
            updatedAt: new Date(op.updatedAt),
            deletedAt: op.deletedAt ? new Date(op.deletedAt) : null,
            payload: op.payload ?? null,
          };
          await this.materializer.apply(tx as unknown as DbClient, materialize);

          applied.push({ opId: op.opId, seq: inserted.seq });
        }

        await tx
          .update(devices)
          .set({ lastSyncAt: new Date(), lastSeenAt: new Date() })
          .where(eq(devices.id, user.deviceId));
      });
    } catch (error) {
      // A transaction referencing an entity whose op never arrived (e.g. a
      // lost LWW loser, a crashed client) surfaces as a FK violation. Surface
      // it as a stable 409 so the client can flag "needs attention" instead of
      // an opaque 500. The constraint name is included for diagnostics.
      // Everything else rethrows (the filter handles 5xx).
      if (isPgError(error, '23503')) {
        const constraint = (error as { cause?: { constraint?: unknown } })?.cause
          ?.constraint;
        throw new ConflictException(
          typeof constraint === 'string'
            ? `Operation references an entity that does not exist (${constraint})`
            : 'Operation references an entity that does not exist',
        );
      }
      // Duplicate key: a client reusing an `opId` across entities hits the
      // global `sync_ops_op_id_unique`; a duplicate current-state row is a
      // client bug (materializer dedupes tags/entries, so this should be
      // rare). Either way it's the client's mistake — 409, never a 500.
      if (isPgError(error, '23505')) {
        throw new ConflictException(
          'Duplicate operation id or row — the client must not reuse opIds or emit duplicate rows',
        );
      }
      throw error;
    }

    const serverCursor =
      applied.length === 0
        ? null // nothing advanced — do NOT conflate with the "fresh" cursor 0
        : Math.max(...applied.map((a) => a.seq));
    return { applied, conflicts, serverCursor };
  }

  /**
   * CAS (base > stored) or LWW (stored wins) rejection. Returns `true` when
   * the incoming op must NOT be applied and should surface as a conflict.
   */
  private rejects(
    current: CurrentState | null,
    op: SyncOpDto,
  ): boolean {
    const currentVersion = current?.version ?? 0;
    if (op.baseVersion > currentVersion) {
      return true; // CAS mismatch — client must re-base.
    }
    if (current === null) {
      return false; // Fresh entity — nothing to compare against.
    }
    const winner = lwwWinner(
      {
        version: current.version,
        updatedAt: current.updatedAt,
        opId: current.opId,
      },
      {
        version: op.version,
        updatedAt: new Date(op.updatedAt),
        opId: op.opId,
      },
    );
    return winner === 'current';
  }

  async pull(
    user: CurrentUser,
    cursor: number,
    limit: number,
  ): Promise<{
    ops: {
      opId: string;
      entity: string;
      entityId: string;
      deviceId: string;
      operation: string;
      baseVersion: number;
      version: number;
      payload: Record<string, unknown> | null;
      updatedAt: string;
      deletedAt: string | null;
    }[];
    nextCursor: number;
    truncated: boolean;
  }> {
    await this.assertDeviceActive(user.userId, user.deviceId);

    const pageSize = Math.min(Math.max(limit, 1), MAX_PULL_PAGE);
    const db = this.database.db;
    const rows = await db
      .select()
      .from(syncOps)
      .where(and(eq(syncOps.userId, user.userId), gt(syncOps.seq, cursor)))
      .orderBy(asc(syncOps.seq))
      .limit(pageSize + 1);

    const truncated = rows.length > pageSize;
    const page = truncated ? rows.slice(0, pageSize) : rows;

    // Parent-first for the client's FK-enforcing local DB (stable sort keeps
    // server order within each group).
    const ordered = [...page].sort(
      (a, b) =>
        (SyncService.ENTITY_PRIORITY[a.entity] ?? 0) -
        (SyncService.ENTITY_PRIORITY[b.entity] ?? 0),
    );

    const ops = ordered.map((r) => ({
      opId: r.opId,
      entity: r.entity,
      entityId: r.entityId,
      deviceId: r.deviceId,
      operation: r.operation,
      baseVersion: r.baseVersion,
      version: r.version,
      payload: (r.payload ?? null) as Record<string, unknown> | null,
      updatedAt: r.updatedAt.toISOString(),
      deletedAt: r.deletedAt?.toISOString() ?? null,
    }));

    await db
      .update(devices)
      .set({ lastSyncAt: new Date(), lastSeenAt: new Date() })
      .where(eq(devices.id, user.deviceId));

    const nextCursor =
      ordered.length === 0
        ? 0
        : Math.max(...ordered.map((o) => o.seq));
    return {
      ops,
      nextCursor: truncated ? nextCursor : 0,
      truncated,
    };
  }

  /** A revoked device must not be able to push/pull (403, per §3). */
  private async assertDeviceActive(
    userId: string,
    deviceId: string,
  ): Promise<void> {
    const db = this.database.db;
    const [device] = await db
      .select({ revokedAt: devices.revokedAt })
      .from(devices)
      .where(and(eq(devices.id, deviceId), eq(devices.userId, userId)));
    if (!device) {
      throw new NotFoundException('Device not found');
    }
    if (device.revokedAt) {
      throw new ForbiddenException('Device has been revoked');
    }
  }
}
