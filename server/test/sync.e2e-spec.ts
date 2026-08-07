// Test environment first — ConfigModule validates at module compile time.
process.env.NODE_ENV = 'test';
process.env.DATABASE_URL ??= 'postgres://finflow:finflow-dev-pass@127.0.0.1:54321/finflow';
process.env.JWT_ACCESS_SECRET ??= 'e2e-test-secret-0123456789abcdef0123456789abcdef';
process.env.THROTTLE_LIMIT = '10000';
process.env.AUTH_MAX_ATTEMPTS_PER_MINUTE = '10000';
process.env.AUTH_MAX_FAILURES_PER_HOUR = '10000';
process.env.LOG_LEVEL = 'silent';
process.env.REDIS_URL = '';
process.env.MINIO_ENDPOINT = ''; // storage disabled in non-storage suites // tests use the in-memory limiter (no docker-internal host)

import { Test } from '@nestjs/testing';
import { NestExpressApplication } from '@nestjs/platform-express';
import { sql } from 'drizzle-orm';
import request from 'supertest';
import { randomUUID } from 'node:crypto';
import { configureApp } from '../src/app.setup';
import { AppModule } from '../src/app.module';
import { DatabaseService } from '../src/database/database.service';
import { MailService } from '../src/mail/mail.service';

/**
 * Sync engine integration suite — runs against REAL PostgreSQL:
 *
 *   docker compose -f docker-compose.yml -f docker-compose.test.yml \
 *     up -d postgres migrate
 *   npm run test:e2e
 *
 * Exercises the full op-log protocol from docs/BACKEND_API.md §4.
 */
describe('Sync (e2e)', () => {
  let app: NestExpressApplication;
  let database: DatabaseService;

  const EMAIL = 'carol@example.com';
  const PASSWORD = 'correct-horse-battery-staple';
  const device = randomUUID();

  const fakeMail = {
    enabled: true,
    sendVerification: jest.fn(async () => true),
    sendPasswordReset: jest.fn(async () => true),
  };

  beforeAll(async () => {
    const moduleRef = await Test.createTestingModule({ imports: [AppModule] })
      .overrideProvider(MailService)
      .useValue(fakeMail)
      .compile();

    app = moduleRef.createNestApplication<NestExpressApplication>();
    configureApp(app);
    await app.init();

    database = app.get(DatabaseService);
    await database.db.execute(
      sql`TRUNCATE TABLE sync_ops, ledger_entries, transaction_tags, app_settings,
        transactions, accounts, bills, budgets, tags,
        refresh_tokens, devices, users, password_reset_tokens CASCADE`,
    );
  });

  afterAll(async () => {
    await app.close();
  });

  const http = () => request(app.getHttpServer());

  /** Sign up (once) + log in a user on the given device. */
  async function login(
    email = EMAIL,
    deviceId = device,
  ): Promise<{ token: string; deviceId: string; email: string }> {
    // 409 = the account already exists from an earlier describe — fine.
    await http()
      .post('/v1/auth/signup')
      .send({ email, password: PASSWORD })
      .then((res) => {
        if (res.status !== 201 && res.status !== 409) {
          throw new Error(`signup failed with ${res.status}`);
        }
      });
    const res = await http()
      .post('/v1/auth/login')
      .send({ email, password: PASSWORD, deviceId, platform: 'web' })
      .expect(200);
    return { token: res.body.accessToken, deviceId, email };
  }

  // --- helpers to build ops -------------------------------------------------

  interface OpInput {
    entity: string;
    entityId: string;
    operation?: 'upsert' | 'delete';
    baseVersion?: number;
    version?: number;
    payload?: Record<string, unknown> | null;
    updatedAt?: string;
    deletedAt?: string | null;
  }

  function op(input: OpInput, deviceId: string = device) {
    return {
      opId: randomUUID(),
      deviceId,
      entity: input.entity,
      entityId: input.entityId,
      operation: input.operation ?? 'upsert',
      baseVersion: input.baseVersion ?? 0,
      version: input.version ?? 1,
      payload: input.payload ?? null,
      updatedAt: input.updatedAt ?? new Date().toISOString(),
      deletedAt: input.deletedAt ?? null,
    };
  }

  const iso = (msOffsetHours: number) =>
    new Date(Date.now() + msOffsetHours * 3_600_000).toISOString();

  // --- fixtures --------------------------------------------------------------

  const CASH = {
    id: 'acct-cash',
    name: 'Cash Wallet',
    kind: 'asset',
    type: 'wallet',
    status: 'active',
    opening_balance_minor: 100000,
    currency_code: 'PHP',
    color_value: 0xff0000,
    sort_order: 1,
    is_hidden: false,
    created_at: iso(-2),
    updated_at: iso(-2),
  };

  const FOOD = {
    id: 'acct-food',
    name: 'Food & Drinks',
    kind: 'expense',
    type: 'category',
    status: 'active',
    opening_balance_minor: 0,
    currency_code: 'PHP',
    color_value: 0x00ff00,
    created_at: iso(-2),
    updated_at: iso(-2),
  };

  const GROCERIES = { id: 'tag-groceries', name: 'Groceries', color_value: 0x0000ff, created_at: iso(-2), updated_at: iso(-2) };

  const LUNCH = {
    id: 'txn-lunch',
    type: 'expense',
    amount_minor: 25000,
    currency_code: 'PHP',
    occurred_at: iso(-1),
    note: 'Lunch',
    merchant: 'Karenderia',
    created_at: iso(-1),
    updated_at: iso(-1),
    ledgerEntries: [
      { id: 'le-1', account_id: CASH.id, direction: 'credit', amount_minor: 25000, currency_code: 'PHP' },
      { id: 'le-2', account_id: FOOD.id, direction: 'debit', amount_minor: 25000, currency_code: 'PHP' },
    ],
    transactionTags: [{ tag_id: GROCERIES.id }],
  };

  // --- tests -----------------------------------------------------------------

  it('requires a bearer token', async () => {
    const res = await http().get('/v1/sync/pull').expect(401);
    expect(res.body.error.code).toBe('UNAUTHORIZED');
  });

  describe('push + pull round-trip', () => {
    let loginRes: Awaited<ReturnType<typeof login>>;
    let serverCursor = 0;

    beforeAll(async () => {
      loginRes = await login();
    });

    it('applies a full batch (account, tag, transaction, bill, budget, setting)', async () => {
      const res = await http()
        .post('/v1/sync/push')
        .set('Authorization', `Bearer ${loginRes.token}`)
        .send({
          ops: [
            op({ entity: 'account', entityId: CASH.id, payload: CASH }),
            op({ entity: 'account', entityId: FOOD.id, payload: FOOD }),
            op({ entity: 'tag', entityId: GROCERIES.id, payload: GROCERIES }),
            op({ entity: 'transaction', entityId: LUNCH.id, payload: LUNCH }),
            op({
              entity: 'bill',
              entityId: 'bill-rent',
              payload: {
                id: 'bill-rent',
                name: 'Rent',
                amount_minor: 1500000,
                currency_code: 'PHP',
                account_id: CASH.id,
                due_day_of_month: 1,
                reminder_days_before: 3,
                is_active: true,
                created_at: iso(-2),
                updated_at: iso(-2),
              },
            }),
            op({
              entity: 'budget',
              entityId: 'budget-food',
              payload: {
                id: 'budget-food',
                category_id: FOOD.id,
                amount_minor: 800000,
                currency_code: 'PHP',
                created_at: iso(-2),
                updated_at: iso(-2),
              },
            }),
            op({
              entity: 'app_setting',
              entityId: 'theme.mode',
              payload: { key: 'theme.mode', value: 'dark', updated_at: iso(-2) },
            }),
          ],
        })
        .expect(200);

      expect(res.body.conflicts).toEqual([]);
      expect(res.body.applied).toHaveLength(7);
      expect(res.body.serverCursor).toBeGreaterThan(0);
      serverCursor = res.body.serverCursor;
      const seqs = res.body.applied.map((a: { seq: number }) => a.seq);
      expect(Math.max(...seqs)).toBe(serverCursor);
    });

    it('pulls back the ops, parent-first, with a repeatable cursor', async () => {
      const first = await http()
        .get('/v1/sync/pull?cursor=0')
        .set('Authorization', `Bearer ${loginRes.token}`)
        .expect(200);
      expect(first.body.ops).toHaveLength(7);
      expect(first.body.nextCursor).toBe(0);
      expect(first.body.truncated).toBe(false);

      const entities = first.body.ops.map((o: { entity: string }) => o.entity);
      // parents (accounts/tags/settings) strictly before children (bills/budgets/transactions)
      const firstTxn = entities.indexOf('transaction');
      const lastParent = Math.max(
        entities.lastIndexOf('account'),
        entities.lastIndexOf('tag'),
        entities.lastIndexOf('app_setting'),
      );
      expect(lastParent).toBeLessThan(firstTxn);
      expect(entities.indexOf('bill')).toBeLessThan(firstTxn);
      expect(entities.indexOf('budget')).toBeLessThan(firstTxn);

      // The transaction op carries its children as a consistent set.
      const txnOp = first.body.ops.find((o: { entityId: string }) => o.entityId === LUNCH.id);
      expect(txnOp.payload.ledgerEntries).toHaveLength(2);
      expect(txnOp.payload.transactionTags).toEqual([{ tag_id: GROCERIES.id }]);

      // Repeatability — same cursor, same ops.
      const again = await http()
        .get('/v1/sync/pull?cursor=0')
        .set('Authorization', `Bearer ${loginRes.token}`)
        .expect(200);
      expect(again.body.ops.map((o: { opId: string }) => o.opId)).toEqual(
        first.body.ops.map((o: { opId: string }) => o.opId),
      );

      // Pulling past the push cursor returns nothing new.
      const caughtUp = await http()
        .get(`/v1/sync/pull?cursor=${serverCursor}`)
        .set('Authorization', `Bearer ${loginRes.token}`)
        .expect(200);
      expect(caughtUp.body.ops).toHaveLength(0);
    });

    it('materialises current state into the mirror tables', async () => {
      const accounts = await database.db.execute(
        sql`SELECT id, name, version, deleted_at FROM accounts WHERE user_id IS NOT NULL`,
      );
      const rows = accounts.rows as { id: string; name: string; version: number }[];
      const cash = rows.find((r) => r.id === CASH.id);
      expect(cash?.name).toBe('Cash Wallet');
      expect(cash?.version).toBe(1);

      const entries = await database.db.execute(
        sql`SELECT id FROM ledger_entries WHERE transaction_id = ${LUNCH.id}`,
      );
      expect(entries.rows).toHaveLength(2);

      const txnTags = await database.db.execute(
        sql`SELECT tag_id FROM transaction_tags WHERE transaction_id = ${LUNCH.id}`,
      );
      expect(txnTags.rows).toHaveLength(1);

      const setting = await database.db.execute(
        sql`SELECT value FROM app_settings WHERE key = 'theme.mode'`,
      );
      expect(setting.rows[0].value).toBe('dark');
    });

    it('is idempotent — replaying the same opIds returns the original seqs', async () => {
      const before = await http()
        .get('/v1/sync/pull?cursor=0')
        .set('Authorization', `Bearer ${loginRes.token}`)
        .expect(200);

      // Push the exact original ops twice — the second replay must return the
      // SAME seqs as the first (idempotent ack), and nothing new lands in the
      // log. (The pull envelope carries no `seq` by contract, so identical
      // ack-seq across replays is the observable of idempotency.)
      const pushBatch = (ops: Record<string, unknown>[]) =>
        http()
          .post('/v1/sync/push')
          .set('Authorization', `Bearer ${loginRes.token}`)
          .send({
            ops: ops.map((o) => ({
              opId: o.opId,
              deviceId: o.deviceId,
              entity: o.entity,
              entityId: o.entityId,
              operation: o.operation,
              baseVersion: o.baseVersion,
              version: o.version,
              payload: o.payload,
              updatedAt: o.updatedAt,
              deletedAt: o.deletedAt,
            })),
          })
          .expect(200);

      const originalOps = before.body.ops;
      const first = await pushBatch(originalOps);
      const second = await pushBatch(originalOps);
      expect(first.body.conflicts).toEqual([]);
      expect(second.body.conflicts).toEqual([]);
      expect(first.body.applied).toHaveLength(originalOps.length);
      expect(second.body.applied.map((a: { seq: number }) => a.seq)).toEqual(
        first.body.applied.map((a: { seq: number }) => a.seq),
      );

      const after = await http()
        .get('/v1/sync/pull?cursor=0')
        .set('Authorization', `Bearer ${loginRes.token}`)
        .expect(200);
      expect(after.body.ops.length).toBe(before.body.ops.length);
    });
  });

  describe('conflict handling', () => {
    // Self-contained entity (distinct from the round-trip fixtures) so this
    // describe's log assertions are isolated from the other describes' data.
    const CONFLICT_ACCOUNT = {
      ...CASH,
      id: 'acct-conflict',
      name: 'Conflict Wallet',
      created_at: iso(-2),
      updated_at: iso(-2),
    };
    let loginRes: Awaited<ReturnType<typeof login>>;

    beforeAll(async () => {
      loginRes = await login();
      await http()
        .post('/v1/sync/push')
        .set('Authorization', `Bearer ${loginRes.token}`)
        .send({
          ops: [op({ entity: 'account', entityId: CONFLICT_ACCOUNT.id, payload: CONFLICT_ACCOUNT })],
        })
        .expect(200);
    });

    it('rejects a CAS mismatch (baseVersion > stored) with the current state', async () => {
      const res = await http()
        .post('/v1/sync/push')
        .set('Authorization', `Bearer ${loginRes.token}`)
        .send({
          ops: [
            op({
              entity: 'account',
              entityId: CONFLICT_ACCOUNT.id,
              baseVersion: 999,
              version: 1000,
              payload: { ...CONFLICT_ACCOUNT, name: 'Hacked Wallet' },
            }),
          ],
        })
        .expect(200);
      expect(res.body.applied).toEqual([]);
      expect(res.body.conflicts).toHaveLength(1);
      expect(res.body.conflicts[0].current.name).toBe('Conflict Wallet');
      expect(res.body.conflicts[0].current.version).toBe(1);
    });

    it('rejects a stale op when LWW says the stored state wins', async () => {
      // version 1 == stored, but older updatedAt → stored wins.
      const res = await http()
        .post('/v1/sync/push')
        .set('Authorization', `Bearer ${loginRes.token}`)
        .send({
          ops: [
            op({
              entity: 'account',
              entityId: CONFLICT_ACCOUNT.id,
              version: 1,
              updatedAt: iso(-48),
              payload: { ...CONFLICT_ACCOUNT, name: 'Ancient Edit' },
            }),
          ],
        })
        .expect(200);
      expect(res.body.conflicts).toHaveLength(1);
      expect(res.body.conflicts[0].current.name).toBe('Conflict Wallet');
    });

    it('applies a stale op that actually wins (higher version)', async () => {
      const res = await http()
        .post('/v1/sync/push')
        .set('Authorization', `Bearer ${loginRes.token}`)
        .send({
          ops: [
            op({
              entity: 'account',
              entityId: CONFLICT_ACCOUNT.id,
              baseVersion: 1,
              version: 2,
              payload: { ...CONFLICT_ACCOUNT, name: 'Conflict Wallet v2', updated_at: iso(1) },
            }),
          ],
        })
        .expect(200);
      expect(res.body.conflicts).toEqual([]);
      expect(res.body.applied).toHaveLength(1);

      const pull = await http()
        .get('/v1/sync/pull?cursor=0')
        .set('Authorization', `Bearer ${loginRes.token}`)
        .expect(200);
      // Only APPLIED ops land in the log: the create (v1) + this v2. The two
      // rejected ops (CAS + stale-LWW) must never appear.
      const accountOps = pull.body.ops.filter(
        (o: { entityId: string }) => o.entityId === CONFLICT_ACCOUNT.id,
      );
      expect(accountOps).toHaveLength(2);
      expect(accountOps.map((o: { version: number }) => o.version)).toEqual([1, 2]);
    });
  });

  describe('ledger integrity', () => {
    let loginRes: Awaited<ReturnType<typeof login>>;

    beforeAll(async () => {
      loginRes = await login();
    });

    it('rejects an unbalanced transaction payload with LEDGER_IMBALANCE', async () => {
      const res = await http()
        .post('/v1/sync/push')
        .set('Authorization', `Bearer ${loginRes.token}`)
        .send({
          ops: [
            op({
              entity: 'transaction',
              entityId: 'txn-bad',
              payload: {
                ...LUNCH,
                id: 'txn-bad',
                amount_minor: 30000,
                // credit 25000 vs debit 20000 → genuinely unbalanced.
                ledgerEntries: [
                  { id: 'le-b1', account_id: CASH.id, direction: 'credit', amount_minor: 25000, currency_code: 'PHP' },
                  { id: 'le-b2', account_id: FOOD.id, direction: 'debit', amount_minor: 20000, currency_code: 'PHP' },
                ],
              },
            }),
          ],
        })
        .expect(409);
      expect(res.body.error.code).toBe('LEDGER_IMBALANCE');

      // The rejected op must not appear in the log.
      const pull = await http()
        .get('/v1/sync/pull?cursor=0')
        .set('Authorization', `Bearer ${loginRes.token}`)
        .expect(200);
      expect(
        pull.body.ops.some((o: { entityId: string }) => o.entityId === 'txn-bad'),
      ).toBe(false);
    });

    it('fails the WHOLE batch fast when any transaction is unbalanced (nothing applied)', async () => {
      const goodAccount = { ...CASH, id: 'acct-good-but-rolled-back' };
      const res = await http()
        .post('/v1/sync/push')
        .set('Authorization', `Bearer ${loginRes.token}`)
        .send({
          ops: [
            op({ entity: 'account', entityId: goodAccount.id, payload: goodAccount }),
            op({
              entity: 'transaction',
              entityId: 'txn-bad-2',
              payload: {
                ...LUNCH,
                id: 'txn-bad-2',
                ledgerEntries: [
                  { id: 'le-c1', account_id: goodAccount.id, direction: 'credit', amount_minor: 25000, currency_code: 'PHP' },
                  { id: 'le-c2', account_id: FOOD.id, direction: 'debit', amount_minor: 10000, currency_code: 'PHP' },
                ],
              },
            }),
          ],
        })
        .expect(409);
      expect(res.body.error.code).toBe('LEDGER_IMBALANCE');

      // Fail-fast means the good account op never landed either.
      const pull = await http()
        .get('/v1/sync/pull?cursor=0')
        .set('Authorization', `Bearer ${loginRes.token}`)
        .expect(200);
      expect(
        pull.body.ops.some((o: { entityId: string }) => o.entityId === goodAccount.id),
      ).toBe(false);
    });

    it('maps a missing referenced account to 409, not 500', async () => {
      const res = await http()
        .post('/v1/sync/push')
        .set('Authorization', `Bearer ${loginRes.token}`)
        .send({
          ops: [
            op({
              entity: 'transaction',
              entityId: 'txn-orphan',
              payload: {
                ...LUNCH,
                id: 'txn-orphan',
                ledgerEntries: [
                  { id: 'le-o1', account_id: 'account-that-never-existed', direction: 'credit', amount_minor: 25000, currency_code: 'PHP' },
                  { id: 'le-o2', account_id: 'account-that-never-existed-2', direction: 'debit', amount_minor: 25000, currency_code: 'PHP' },
                ],
              },
            }),
          ],
        })
        .expect(409);
      expect(res.body.error.code).toBe('CONFLICT');
    });
  });

  describe('same entity id across users (composite keys)', () => {
    // The app seeds DETERMINISTIC ids (system account + 32 default categories)
    // on every install — so two users MUST be able to own the same id. This
    // is the regression test for the global-PK bug (was: 23505 → 500).
    it('lets two users own the same seeded-style id without collision', async () => {
      const alice = await login('alice@example.com', randomUUID());
      const bob = await login('bob@example.com', randomUUID());
      const sharedId = 'cat-seeded-food';
      const shared: Record<string, unknown> = {
        id: sharedId,
        name: 'Food & Drinks',
        kind: 'expense',
        type: 'category',
        status: 'active',
        opening_balance_minor: 0,
        currency_code: 'PHP',
        color_value: 65280,
        created_at: iso(-2),
        updated_at: iso(-2),
      };

      const pushAlice = await http()
        .post('/v1/sync/push')
        .set('Authorization', `Bearer ${alice.token}`)
        .send({ ops: [op({ entity: 'account', entityId: sharedId, payload: shared }, alice.deviceId)] })
        .expect(200);
      expect(pushAlice.body.conflicts).toEqual([]);
      expect(pushAlice.body.applied).toHaveLength(1);

      // Bob pushes the SAME id — previously this 500'd on the global PK.
      const pushBob = await http()
        .post('/v1/sync/push')
        .set('Authorization', `Bearer ${bob.token}`)
        .send({ ops: [op({ entity: 'account', entityId: sharedId, payload: shared }, bob.deviceId)] })
        .expect(200);
      expect(pushBob.body.conflicts).toEqual([]);
      expect(pushBob.body.applied).toHaveLength(1);

      // Each user's log has exactly their own op.
      const alicePull = await http()
        .get('/v1/sync/pull?cursor=0')
        .set('Authorization', `Bearer ${alice.token}`)
        .expect(200);
      const bobPull = await http()
        .get('/v1/sync/pull?cursor=0')
        .set('Authorization', `Bearer ${bob.token}`)
        .expect(200);
      expect(alicePull.body.ops).toHaveLength(1);
      expect(bobPull.body.ops).toHaveLength(1);

      // Both rows materialise (composite PK (user_id, id)).
      const rows = await database.db.execute(
        sql`SELECT count(*)::int AS n FROM accounts WHERE id = 'cat-seeded-food'`,
      );
      expect(rows.rows[0].n).toBe(2);
    });

    it('scopes current-state reads to the owner (no cross-user reads)', async () => {
      // Alice's later edit of the shared id must NOT affect Bob's copy.
      const alice = await login('alice@example.com', randomUUID());
      const bob = await login('bob@example.com', randomUUID());

      await http()
        .post('/v1/sync/push')
        .set('Authorization', `Bearer ${alice.token}`)
        .send({
          ops: [
            op(
              {
                entity: 'account',
                entityId: 'shared-wallet',
                payload: { ...CASH, id: 'shared-wallet', name: 'Alice Wallet' },
              },
              alice.deviceId,
            ),
          ],
        })
        .expect(200);

      // Bob pushes an edit to the same id — base 0 version 1, since HIS copy
      // is fresh. Must be applied (not LWW'd against Alice's row).
      const bobPush = await http()
        .post('/v1/sync/push')
        .set('Authorization', `Bearer ${bob.token}`)
        .send({
          ops: [
            op(
              {
                entity: 'account',
                entityId: 'shared-wallet',
                payload: { ...CASH, id: 'shared-wallet', name: 'Bob Wallet' },
              },
              bob.deviceId,
            ),
          ],
        })
        .expect(200);
      expect(bobPush.body.conflicts).toEqual([]);

      const rows = await database.db.execute(
        sql`SELECT name FROM accounts WHERE id = 'shared-wallet' ORDER BY name`,
      );
      const names = (rows.rows as { name: string }[]).map((r) => r.name);
      expect(names).toContain('Alice Wallet');
      expect(names).toContain('Bob Wallet');
    });
  });

  describe('deletes', () => {
    let loginRes: Awaited<ReturnType<typeof login>>;

    beforeAll(async () => {
      loginRes = await login();
      await http()
        .post('/v1/sync/push')
        .set('Authorization', `Bearer ${loginRes.token}`)
        .send({
          ops: [
            op({ entity: 'account', entityId: CASH.id, payload: CASH }),
            op({ entity: 'account', entityId: FOOD.id, payload: FOOD }),
            op({ entity: 'tag', entityId: GROCERIES.id, payload: GROCERIES }),
            op({ entity: 'transaction', entityId: LUNCH.id, payload: LUNCH }),
          ],
        })
        .expect(200);
    });

    it('soft-deletes accounts (never a hard delete) and removes txn children', async () => {
      const res = await http()
        .post('/v1/sync/push')
        .set('Authorization', `Bearer ${loginRes.token}`)
        .send({
          ops: [
            op({
              entity: 'transaction',
              entityId: LUNCH.id,
              operation: 'delete',
              baseVersion: 1,
              version: 2,
            }),
            op({
              entity: 'account',
              entityId: FOOD.id,
              operation: 'delete',
              baseVersion: 1,
              version: 2,
            }),
          ],
        })
        .expect(200);
      expect(res.body.conflicts).toEqual([]);

      const txn = await database.db.execute(
        sql`SELECT deleted_at FROM transactions WHERE id = ${LUNCH.id}`,
      );
      expect(txn.rows[0].deleted_at).not.toBeNull();

      // Transaction children are removed so derived balances stay clean.
      const entries = await database.db.execute(
        sql`SELECT count(*)::int AS n FROM ledger_entries WHERE transaction_id = ${LUNCH.id}`,
      );
      expect(entries.rows[0].n).toBe(0);

      // The account row still exists (soft delete) — ledger entries can still
      // reference it without violating the RESTRICT FK.
      const acct = await database.db.execute(
        sql`SELECT deleted_at FROM accounts WHERE id = ${FOOD.id}`,
      );
      expect(acct.rows[0].deleted_at).not.toBeNull();

      // The delete ops are in the log so other devices converge.
      const pull = await http()
        .get('/v1/sync/pull?cursor=0')
        .set('Authorization', `Bearer ${loginRes.token}`)
        .expect(200);
      const deletes = pull.body.ops.filter((o: { operation: string }) => o.operation === 'delete');
      expect(deletes).toHaveLength(2);
    });

    it('revives a soft-deleted account on a newer upsert', async () => {
      const res = await http()
        .post('/v1/sync/push')
        .set('Authorization', `Bearer ${loginRes.token}`)
        .send({
          ops: [
            op({
              entity: 'account',
              entityId: FOOD.id,
              baseVersion: 2,
              version: 3,
              payload: { ...FOOD, name: 'Food & Drinks (revived)', updated_at: iso(2) },
            }),
          ],
        })
        .expect(200);
      expect(res.body.conflicts).toEqual([]);

      const acct = await database.db.execute(
        sql`SELECT deleted_at FROM accounts WHERE id = ${FOOD.id}`,
      );
      expect(acct.rows[0].deleted_at).toBeNull();
    });
  });

  describe('security & isolation', () => {
    let carol: Awaited<ReturnType<typeof login>>;
    let dave: Awaited<ReturnType<typeof login>>;
    const daveDevice = randomUUID();

    beforeAll(async () => {
      carol = await login(EMAIL);
      dave = await login('dave@example.com', daveDevice);
    });

    it('rejects ops whose deviceId does not match the token device', async () => {
      const res = await http()
        .post('/v1/sync/push')
        .set('Authorization', `Bearer ${carol.token}`)
        .send({
          ops: [
            {
              ...op({ entity: 'account', entityId: 'acct-x', payload: { ...CASH, id: 'acct-x' } }),
              deviceId: daveDevice, // mismatch
            },
          ],
        })
        .expect(403);
      expect(res.body.error.code).toBe('FORBIDDEN');
    });

    it('isolates users — Dave never sees Carol\'s ops', async () => {
      const carolPull = await http()
        .get('/v1/sync/pull?cursor=0')
        .set('Authorization', `Bearer ${carol.token}`)
        .expect(200);
      expect(carolPull.body.ops.length).toBeGreaterThan(0);

      const davePull = await http()
        .get('/v1/sync/pull?cursor=0')
        .set('Authorization', `Bearer ${dave.token}`)
        .expect(200);
      expect(davePull.body.ops).toHaveLength(0);

      // Dave pushes his own data and it stays his.
      await http()
        .post('/v1/sync/push')
        .set('Authorization', `Bearer ${dave.token}`)
        .send({
          ops: [
            op(
              {
                entity: 'account',
                entityId: 'dave-wallet',
                payload: { ...CASH, id: 'dave-wallet', name: "Dave's Wallet" },
              },
              daveDevice,
            ),
          ],
        })
        .expect(200);
      const daveAfter = await http()
        .get('/v1/sync/pull?cursor=0')
        .set('Authorization', `Bearer ${dave.token}`)
        .expect(200);
      expect(daveAfter.body.ops).toHaveLength(1);

      const carolStill = await http()
        .get('/v1/sync/pull?cursor=0')
        .set('Authorization', `Bearer ${carol.token}`)
        .expect(200);
      expect(carolStill.body.ops.some((o: { entityId: string }) => o.entityId === 'dave-wallet')).toBe(false);
    });

    it('rejects pushes from a revoked device (403)', async () => {
      // Dave logs in on a second install, then revokes his FIRST device.
      const daveDevice2 = randomUUID();
      const dave2 = await http()
        .post('/v1/auth/login')
        .send({
          email: dave.email,
          password: PASSWORD,
          deviceId: daveDevice2,
          platform: 'android',
        })
        .expect(200);
      await http()
        .delete(`/v1/devices/${daveDevice}`)
        .set('Authorization', `Bearer ${dave2.body.accessToken}`)
        .expect(204);

      // Dave's old access token (still valid for 15 min) can no longer sync.
      const push = await http()
        .post('/v1/sync/push')
        .set('Authorization', `Bearer ${dave.token}`)
        .send({
          ops: [
            op(
              {
                entity: 'account',
                entityId: 'acct-y',
                payload: { ...CASH, id: 'acct-y' },
              },
              daveDevice,
            ),
          ],
        })
        .expect(403);
      expect(push.body.error.code).toBe('FORBIDDEN');

      const pull = await http()
        .get('/v1/sync/pull?cursor=0')
        .set('Authorization', `Bearer ${dave.token}`)
        .expect(403);
      expect(pull.body.error.code).toBe('FORBIDDEN');
    });
  });

  describe('pagination', () => {
    let loginRes: Awaited<ReturnType<typeof login>>;

    beforeAll(async () => {
      // Fresh user so the log contains exactly the 3 ops pushed below.
      loginRes = await login('pager@example.com', randomUUID());
      await http()
        .post('/v1/sync/push')
        .set('Authorization', `Bearer ${loginRes.token}`)
        .send({
          ops: [1, 2, 3].map((i) =>
            op(
              {
                entity: 'app_setting',
                entityId: `setting.${i}`,
                payload: { key: `setting.${i}`, value: `v${i}`, updated_at: iso(-1) },
              },
              loginRes.deviceId,
            ),
          ),
        })
        .expect(200);
    });

    it('pages with a cursor and stops cleanly at the end', async () => {
      const page1 = await http()
        .get('/v1/sync/pull?cursor=0&limit=2')
        .set('Authorization', `Bearer ${loginRes.token}`)
        .expect(200);
      expect(page1.body.ops).toHaveLength(2);
      expect(page1.body.truncated).toBe(true);
      expect(page1.body.nextCursor).toBeGreaterThan(0);

      const page2 = await http()
        .get(`/v1/sync/pull?cursor=${page1.body.nextCursor}&limit=2`)
        .set('Authorization', `Bearer ${loginRes.token}`)
        .expect(200);
      expect(page2.body.ops).toHaveLength(1);
      expect(page2.body.truncated).toBe(false);
      expect(page2.body.nextCursor).toBe(0);

      // No overlap between pages.
      const ids1 = page1.body.ops.map((o: { opId: string }) => o.opId);
      const ids2 = page2.body.ops.map((o: { opId: string }) => o.opId);
      expect(ids1.some((id: string) => ids2.includes(id))).toBe(false);
    });

    it('validates the query params', async () => {
      const res = await http()
        .get('/v1/sync/pull?cursor=-1')
        .set('Authorization', `Bearer ${loginRes.token}`)
        .expect(400);
      expect(res.body.error.code).toBe('VALIDATION_FAILED');
    });
  });

  describe('concurrent pushes (advisory-lock serialisation)', () => {
    let loginRes: Awaited<ReturnType<typeof login>>;

    beforeAll(async () => {
      loginRes = await login();
    });

    it('never applies two competing edits of the same fresh entity', async () => {
      const entityId = 'race-account';
      const newer = iso(5);
      const older = iso(3);
      const pushA = http()
        .post('/v1/sync/push')
        .set('Authorization', `Bearer ${loginRes.token}`)
        .send({
          ops: [
            op({
              entity: 'account',
              entityId,
              updatedAt: newer,
              payload: { ...CASH, id: entityId, name: 'Winner' },
            }),
          ],
        });
      const pushB = http()
        .post('/v1/sync/push')
        .set('Authorization', `Bearer ${loginRes.token}`)
        .send({
          ops: [
            op({
              entity: 'account',
              entityId,
              updatedAt: older,
              payload: { ...CASH, id: entityId, name: 'Loser' },
            }),
          ],
        });

      const [a, b] = await Promise.all([pushA, pushB]);
      const applied = [a, b].filter((r) => r.body.applied.length === 1);
      const conflicts = [a, b].filter((r) => r.body.conflicts.length === 1);
      expect(applied).toHaveLength(1);
      expect(conflicts).toHaveLength(1);

      // The newer updated_at edit wins deterministically.
      expect(applied[0].body.applied[0].opId).toBeTruthy();
      const winnerOp = applied[0].body.applied[0];
      const loserOp = conflicts[0].body.conflicts[0];
      expect(loserOp.current.name).toBe('Winner');

      // Exactly ONE op in the log for the entity (no duplicate versions).
      const row = await database.db.execute(
        sql`SELECT count(*)::int AS n FROM sync_ops WHERE entity_id = ${entityId}`,
      );
      expect(row.rows[0].n).toBe(1);
    });
  });

  describe('payload hardening (review findings)', () => {
    let loginRes: Awaited<ReturnType<typeof login>>;

    beforeAll(async () => {
      loginRes = await login('hardening@example.com', randomUUID());
    });

    // Every op must carry THIS user's device (the op() helper defaults to the
    // shared carol device).
    const own = (input: OpInput) => op(input, loginRes.deviceId);

    it('rejects string-typed money instead of silently coercing to 0', async () => {
      // A web client serialising a large Dart int as a JSON string would
      // previously have its opening balance silently written as 0.
      const res = await http()
        .post('/v1/sync/push')
        .set('Authorization', `Bearer ${loginRes.token}`)
        .send({
          ops: [
            own({
              entity: 'account',
              entityId: 'acct-string-money',
              payload: { ...CASH, id: 'acct-string-money', opening_balance_minor: '100000' },
            }),
          ],
        })
        .expect(400);
      expect(res.body.error.code).toBe('VALIDATION_FAILED');
    });

    it('rejects a boolean-typed field that is not a boolean', async () => {
      const res = await http()
        .post('/v1/sync/push')
        .set('Authorization', `Bearer ${loginRes.token}`)
        .send({
          ops: [
            own({
              entity: 'account',
              entityId: 'acct-bool-str',
              payload: { ...CASH, id: 'acct-bool-str', is_hidden: 'false' },
            }),
          ],
        })
        .expect(400);
      expect(res.body.error.code).toBe('VALIDATION_FAILED');
    });

    it('dedupes duplicate tag ids instead of 500ing on the PK', async () => {
      const res = await http()
        .post('/v1/sync/push')
        .set('Authorization', `Bearer ${loginRes.token}`)
        .send({
          ops: [
            own({ entity: 'account', entityId: CASH.id, payload: CASH }),
            own({ entity: 'account', entityId: FOOD.id, payload: FOOD }),
            own({ entity: 'tag', entityId: GROCERIES.id, payload: GROCERIES }),
            own({
              entity: 'transaction',
              entityId: 'txn-dup-tags',
              payload: {
                ...LUNCH,
                id: 'txn-dup-tags',
                // the same tag listed twice — previously 23505 → 500
                transactionTags: [{ tag_id: GROCERIES.id }, { tag_id: GROCERIES.id }],
              },
            }),
          ],
        })
        .expect(200);
      expect(res.body.conflicts).toEqual([]);
      expect(res.body.applied).toHaveLength(4);

      const rows = await database.db.execute(
        sql`SELECT count(*)::int AS n FROM transaction_tags WHERE transaction_id = 'txn-dup-tags'`,
      );
      expect(rows.rows[0].n).toBe(1);
    });

    it('generates a fresh ledger-entry id when the fallback would collide', async () => {
      // entry 0 claims the id `<txnId>-1` that the generator would assign to
      // entry 1 — the generator must skip past it instead of 500ing.
      const txnId = 'txn-id-collision';
      const res = await http()
        .post('/v1/sync/push')
        .set('Authorization', `Bearer ${loginRes.token}`)
        .send({
          ops: [
            own({ entity: 'account', entityId: CASH.id, payload: CASH }),
            own({ entity: 'account', entityId: FOOD.id, payload: FOOD }),
            own({
              entity: 'transaction',
              entityId: txnId,
              payload: {
                ...LUNCH,
                id: txnId,
                ledgerEntries: [
                  { id: `${txnId}-1`, account_id: CASH.id, direction: 'credit', amount_minor: 25000, currency_code: 'PHP' },
                  { account_id: FOOD.id, direction: 'debit', amount_minor: 25000, currency_code: 'PHP' }, // no id → generated
                ],
              },
            }),
          ],
        })
        .expect(200);
      expect(res.body.conflicts).toEqual([]);

      const rows = await database.db.execute(
        sql`SELECT id FROM ledger_entries WHERE transaction_id = ${txnId} ORDER BY id`,
      );
      const ids = (rows.rows as { id: string }[]).map((r) => r.id);
      expect(ids).toHaveLength(2);
      // entry 0 keeps its explicit `<txnId>-1`; entry 1's generated id starts
      // at `<txnId>-1`, collides, and must skip to `<txnId>-2` — no 500.
      expect(ids).toEqual([`${txnId}-1`, `${txnId}-2`]);
    });

    it('maps a reused opId across entities to 409, not 500', async () => {
      const sharedOpId = randomUUID();
      const res = await http()
        .post('/v1/sync/push')
        .set('Authorization', `Bearer ${loginRes.token}`)
        .send({
          ops: [
            {
              ...own({ entity: 'account', entityId: 'acct-opid-a', payload: { ...CASH, id: 'acct-opid-a' } }),
              opId: sharedOpId,
            },
            {
              ...own({ entity: 'account', entityId: 'acct-opid-b', payload: { ...CASH, id: 'acct-opid-b' } }),
              opId: sharedOpId, // collision with the first op
            },
          ],
        })
        .expect(409);
      expect(res.body.error.code).toBe('CONFLICT');
    });

    it('returns a null serverCursor when the whole batch conflicts', async () => {
      // Fresh entity so the first push establishes v1; then a CAS-mismatch
      // push conflicts on everything → serverCursor must be null, never 0
      // (0 is the "nothing since the beginning" sentinel on pull).
      const entityId = 'acct-all-conflict';
      await http()
        .post('/v1/sync/push')
        .set('Authorization', `Bearer ${loginRes.token}`)
        .send({
          ops: [own({ entity: 'account', entityId, payload: { ...CASH, id: entityId } })],
        })
        .expect(200);

      const res = await http()
        .post('/v1/sync/push')
        .set('Authorization', `Bearer ${loginRes.token}`)
        .send({
          ops: [
            own({
              entity: 'account',
              entityId,
              baseVersion: 999,
              version: 1000,
              payload: { ...CASH, id: entityId, name: 'Nope' },
            }),
          ],
        })
        .expect(200);
      expect(res.body.applied).toEqual([]);
      expect(res.body.conflicts).toHaveLength(1);
      expect(res.body.serverCursor).toBeNull();
    });
  });

  describe('batch limits', () => {
    let loginRes: Awaited<ReturnType<typeof login>>;

    beforeAll(async () => {
      loginRes = await login('bulk@example.com', randomUUID());
    });

    it('rejects a batch larger than 500 ops', async () => {
      const ops = Array.from({ length: 501 }, (_, i) =>
        op({
          entity: 'app_setting',
          entityId: `bulk.${i}`,
          payload: { key: `bulk.${i}`, value: 'x', updated_at: iso(-1) },
        }),
      );
      const res = await http()
        .post('/v1/sync/push')
        .set('Authorization', `Bearer ${loginRes.token}`)
        .send({ ops })
        .expect(400);
      expect(res.body.error.code).toBe('VALIDATION_FAILED');
    });
  });
});
