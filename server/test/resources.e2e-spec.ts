// Test environment first — ConfigModule validates at module compile time.
process.env.NODE_ENV = 'test';
process.env.DATABASE_URL ??= 'postgres://finflow:finflow-dev-pass@127.0.0.1:54321/finflow';
process.env.JWT_ACCESS_SECRET ??= 'e2e-test-secret-0123456789abcdef0123456789abcdef';
process.env.THROTTLE_LIMIT = '10000';
process.env.AUTH_MAX_ATTEMPTS_PER_MINUTE = '10000';
process.env.AUTH_MAX_FAILURES_PER_HOUR = '10000';
process.env.LOG_LEVEL = 'silent';
process.env.REDIS_URL = ''; // tests use the in-memory limiter (no docker-internal host)
process.env.MINIO_ENDPOINT ??= '';

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
 * Resources + ledger integration suite — the current-state read endpoints
 * (docs/BACKEND_API.md §5–6). Writes go through the op-log engine, so every
 * create/update/delete also lands in sync_ops.
 */
describe('Resources + Ledger (e2e)', () => {
  let app: NestExpressApplication;
  let database: DatabaseService;

  const EMAIL = 'eve@example.com';
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

  async function login(): Promise<{ token: string; deviceId: string }> {
    await http()
      .post('/v1/auth/signup')
      .send({ email: EMAIL, password: PASSWORD })
      .then((res) => {
        if (res.status !== 201 && res.status !== 409) {
          throw new Error(`signup failed with ${res.status}`);
        }
      });
    const res = await http()
      .post('/v1/auth/login')
      .send({ email: EMAIL, password: PASSWORD, deviceId: device, platform: 'web' })
      .expect(200);
    return { token: res.body.accessToken, deviceId: device };
  }

  const iso = (hoursAgo: number) => new Date(Date.now() - hoursAgo * 3_600_000).toISOString();

  let auth: { token: string; deviceId: string };

  beforeAll(async () => {
    auth = await login();
  });

  it('requires a bearer token', async () => {
    await http().get('/v1/accounts').expect(401);
  });

  describe('accounts CRUD via the read endpoints', () => {
    const accountId = 'res-acct-cash';

    it('creates an account (generates an op in sync_ops)', async () => {
      const res = await http()
        .post('/v1/accounts')
        .set('Authorization', `Bearer ${auth.token}`)
        .send({
          id: accountId,
          name: 'Cash Wallet',
          kind: 'asset',
          type: 'wallet',
          status: 'active',
          opening_balance_minor: 100000,
          currency_code: 'PHP',
          color_value: 0xff0000,
          sort_order: 1,
          is_hidden: false,
          created_at: iso(2),
          updated_at: iso(2),
        })
        .expect(201);
      expect(res.body.name).toBe('Cash Wallet');
      expect(res.body.version).toBe(1);

      const op = await database.db.execute(
        sql`SELECT count(*)::int AS n FROM sync_ops WHERE entity_id = ${accountId}`,
      );
      expect(op.rows[0].n).toBe(1);
    });

    it('lists accounts with the collection contract', async () => {
      const res = await http()
        .get('/v1/accounts')
        .set('Authorization', `Bearer ${auth.token}`)
        .expect(200);
      expect(res.body.items).toHaveLength(1);
      expect(res.body.page).toBe(1);
      expect(res.body.total).toBe(1);
      expect(res.body.hasMore).toBe(false);
    });

    it('gets a single account', async () => {
      const res = await http()
        .get(`/v1/accounts/${accountId}`)
        .set('Authorization', `Bearer ${auth.token}`)
        .expect(200);
      expect(res.body.name).toBe('Cash Wallet');
      expect(res.body.opening_balance_minor).toBe(100000);
    });

    it('updates an account (version bumps, op appended)', async () => {
      const res = await http()
        .patch(`/v1/accounts/${accountId}`)
        .set('Authorization', `Bearer ${auth.token}`)
        .send({
          id: accountId,
          name: 'Cash Wallet v2',
          kind: 'asset',
          type: 'wallet',
          status: 'active',
          opening_balance_minor: 100000,
          currency_code: 'PHP',
          color_value: 0xff0000,
          sort_order: 1,
          is_hidden: false,
          created_at: iso(2),
          updated_at: iso(1),
        })
        .expect(200);
      expect(res.body.name).toBe('Cash Wallet v2');
      expect(res.body.version).toBe(2);
    });

    it('soft-deletes an account (removed from reads, op appended)', async () => {
      await http()
        .delete(`/v1/accounts/${accountId}`)
        .set('Authorization', `Bearer ${auth.token}`)
        .expect(204);

      await http()
        .get(`/v1/accounts/${accountId}`)
        .set('Authorization', `Bearer ${auth.token}`)
        .expect(404);

      const list = await http()
        .get('/v1/accounts')
        .set('Authorization', `Bearer ${auth.token}`)
        .expect(200);
      expect(list.body.items).toHaveLength(0);

      // Row still exists (soft delete) — verifiable in the mirror table.
      const rows = await database.db.execute(
        sql`SELECT deleted_at FROM accounts WHERE id = ${accountId}`,
      );
      expect(rows.rows[0].deleted_at).not.toBeNull();
    });
  });

  describe('transactions + ledger', () => {
    const cashId = 'res-txn-cash';
    const foodId = 'res-txn-food';
    const txnId = 'res-txn-lunch';

    beforeAll(async () => {
      // Seed the two accounts (categories) the transaction references.
      const mkAccount = (id: string, name: string, kind: string) =>
        http()
          .post('/v1/accounts')
          .set('Authorization', `Bearer ${auth.token}`)
          .send({
            id,
            name,
            kind,
            type: kind === 'expense' ? 'category' : 'wallet',
            status: 'active',
            opening_balance_minor: 0,
            currency_code: 'PHP',
            color_value: 0x00ff00,
            created_at: iso(3),
            updated_at: iso(3),
          })
          .expect(201);
      await mkAccount(cashId, 'Cash', 'asset');
      await mkAccount(foodId, 'Food', 'expense');
    });

    it('creates a balanced transaction with children', async () => {
      const res = await http()
        .post('/v1/transactions')
        .set('Authorization', `Bearer ${auth.token}`)
        .send({
          id: txnId,
          type: 'expense',
          amount_minor: 25000,
          currency_code: 'PHP',
          occurred_at: iso(1),
          note: 'Lunch',
          merchant: 'Karenderia',
          created_at: iso(1),
          updated_at: iso(1),
          ledgerEntries: [
            { id: 'le-r1', account_id: cashId, direction: 'credit', amount_minor: 25000, currency_code: 'PHP' },
            { id: 'le-r2', account_id: foodId, direction: 'debit', amount_minor: 25000, currency_code: 'PHP' },
          ],
        })
        .expect(201);
      expect(res.body.merchant).toBe('Karenderia');
      expect(res.body.ledgerEntries).toHaveLength(2);
    });

    it('rejects an unbalanced transaction with LEDGER_IMBALANCE', async () => {
      const res = await http()
        .post('/v1/transactions')
        .set('Authorization', `Bearer ${auth.token}`)
        .send({
          id: 'res-txn-bad',
          type: 'expense',
          amount_minor: 30000,
          currency_code: 'PHP',
          occurred_at: iso(1),
          created_at: iso(1),
          updated_at: iso(1),
          ledgerEntries: [
            { id: 'le-b1', account_id: cashId, direction: 'credit', amount_minor: 25000, currency_code: 'PHP' },
            { id: 'le-b2', account_id: foodId, direction: 'debit', amount_minor: 20000, currency_code: 'PHP' },
          ],
        })
        .expect(409);
      expect(res.body.error.code).toBe('LEDGER_IMBALANCE');
    });

    it('returns the derived balance for an account', async () => {
      // Cash: 100000 opening (debit) − 25000 credit (lunch) = 75000.
      // The opening balance row is not created here; the ledger only sums the
      // transaction entries, so cash = −25000 (credit) and food = +25000.
      const cash = await http()
        .get(`/v1/ledger/accounts/${cashId}/balance`)
        .set('Authorization', `Bearer ${auth.token}`)
        .expect(200);
      expect(cash.body.balanceMinor).toBe(-25000);
      expect(cash.body.currencyCode).toBe('PHP');

      const food = await http()
        .get(`/v1/ledger/accounts/${foodId}/balance`)
        .set('Authorization', `Bearer ${auth.token}`)
        .expect(200);
      expect(food.body.balanceMinor).toBe(25000);
    });

    it('returns the ledger entries for a transaction', async () => {
      const res = await http()
        .get(`/v1/ledger/transactions/${txnId}/entries`)
        .set('Authorization', `Bearer ${auth.token}`)
        .expect(200);
      expect(res.body.entries).toHaveLength(2);
      const directions = res.body.entries.map((e: { direction: string }) => e.direction).sort();
      expect(directions).toEqual(['credit', 'debit']);
    });

    it('404s ledger reads for another user\'s account', async () => {
      // Second user: her own account id collides with eve's cash id — the
      // balance query must be scoped by user_id.
      const otherEmail = 'mallory@example.com';
      const otherDevice = randomUUID();
      await http()
        .post('/v1/auth/signup')
        .send({ email: otherEmail, password: PASSWORD })
        .then((res) => {
          if (res.status !== 201 && res.status !== 409) throw new Error('signup failed');
        });
      const otherLogin = await http()
        .post('/v1/auth/login')
        .send({ email: otherEmail, password: PASSWORD, deviceId: otherDevice, platform: 'web' })
        .expect(200);

      const res = await http()
        .get(`/v1/ledger/accounts/${cashId}/balance`)
        .set('Authorization', `Bearer ${otherLogin.body.accessToken}`)
        .expect(404);
      expect(res.body.error.code).toBe('NOT_FOUND');
    });
  });

  describe('tags, bills, budgets, settings', () => {
    it('creates and lists a tag', async () => {
      const tagId = 'res-tag-groceries';
      const res = await http()
        .post('/v1/tags')
        .set('Authorization', `Bearer ${auth.token}`)
        .send({ id: tagId, name: 'Groceries', color_value: 0x0000ff, created_at: iso(2), updated_at: iso(2) })
        .expect(201);
      expect(res.body.name).toBe('Groceries');

      const list = await http()
        .get('/v1/tags')
        .set('Authorization', `Bearer ${auth.token}`)
        .expect(200);
      expect(list.body.items).toHaveLength(1);
    });

    it('creates and lists a bill referencing an account', async () => {
      const cashId = 'res-txn-cash';
      const billId = 'res-bill-rent';
      const res = await http()
        .post('/v1/bills')
        .set('Authorization', `Bearer ${auth.token}`)
        .send({
          id: billId,
          name: 'Rent',
          amount_minor: 1500000,
          currency_code: 'PHP',
          account_id: cashId,
          due_day_of_month: 1,
          reminder_days_before: 3,
          is_active: true,
          created_at: iso(2),
          updated_at: iso(2),
        })
        .expect(201);
      expect(res.body.name).toBe('Rent');

      const list = await http()
        .get('/v1/bills')
        .set('Authorization', `Bearer ${auth.token}`)
        .expect(200);
      expect(list.body.items).toHaveLength(1);
    });

    it('creates and lists a budget referencing a category', async () => {
      const foodId = 'res-txn-food';
      const res = await http()
        .post('/v1/budgets')
        .set('Authorization', `Bearer ${auth.token}`)
        .send({
          id: 'res-budget-food',
          category_id: foodId,
          amount_minor: 800000,
          currency_code: 'PHP',
          created_at: iso(2),
          updated_at: iso(2),
        })
        .expect(201);
      expect(res.body.amount_minor).toBe(800000);
    });

    it('round-trips settings and rejects security.* keys', async () => {
      const res = await http()
        .put('/v1/settings/theme.mode')
        .set('Authorization', `Bearer ${auth.token}`)
        .send({ value: 'dark' })
        .expect(200);
      expect(res.body.value).toBe('dark');

      const list = await http()
        .get('/v1/settings')
        .set('Authorization', `Bearer ${auth.token}`)
        .expect(200);
      expect(list.body.items.map((s: { key: string }) => s.key)).toContain('theme.mode');

      // security.* keys are never readable…
      await http()
        .get('/v1/settings/security.pin_hash')
        .set('Authorization', `Bearer ${auth.token}`)
        .expect(404);

      // …and never writable.
      const denied = await http()
        .put('/v1/settings/security.pin_hash')
        .set('Authorization', `Bearer ${auth.token}`)
        .send({ value: 'x' })
        .expect(400);
      expect(denied.body.error.code).toBe('VALIDATION_FAILED');
    });
  });
});
