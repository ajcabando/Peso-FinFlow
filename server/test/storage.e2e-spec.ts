// Test environment first — ConfigModule validates at module compile time.
process.env.NODE_ENV = 'test';
process.env.DATABASE_URL ??= 'postgres://finflow:finflow-dev-pass@127.0.0.1:54321/finflow';
process.env.JWT_ACCESS_SECRET ??= 'e2e-test-secret-0123456789abcdef0123456789abcdef';
process.env.THROTTLE_LIMIT = '10000';
process.env.AUTH_MAX_ATTEMPTS_PER_MINUTE = '10000';
process.env.AUTH_MAX_FAILURES_PER_HOUR = '10000';
process.env.LOG_LEVEL = 'silent';
process.env.REDIS_URL = ''; // tests use the in-memory limiter (no docker-internal host)
// Real MinIO published by the test compose override (127.0.0.1:19000). Creds
// come from the repo-root .env (MINIO_ROOT_USER/PASSWORD) so the suite talks
// to the exact same MinIO instance the compose stack runs.
process.env.MINIO_ENDPOINT ??= '127.0.0.1';
process.env.MINIO_PORT ??= '19000';
process.env.MINIO_USE_SSL ??= 'false';
process.env.MINIO_BUCKET ??= 'finflow-test';
process.env.BACKUP_RETENTION ??= '2';
{
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  const { config } = require('dotenv');
  const rootEnv = config({ path: '../.env', quiet: true }).parsed ?? {};
  process.env.MINIO_ACCESS_KEY ??=
    process.env.MINIO_ACCESS_KEY ?? rootEnv.MINIO_ROOT_USER ?? 'finflow';
  process.env.MINIO_SECRET_KEY ??=
    process.env.MINIO_SECRET_KEY ?? rootEnv.MINIO_ROOT_PASSWORD ?? 'finflow-dev-pass';
}

import { Test } from '@nestjs/testing';
import { NestExpressApplication } from '@nestjs/platform-express';
import { sql } from 'drizzle-orm';
import request from 'supertest';
import { createHash, randomBytes, randomUUID } from 'node:crypto';
import { configureApp } from '../src/app.setup';
import { AppModule } from '../src/app.module';
import { CleanupService } from '../src/cleanup/cleanup.service';
import { DatabaseService } from '../src/database/database.service';
import { MailService } from '../src/mail/mail.service';
import { MinioService } from '../src/storage/minio.service';

/**
 * Attachments + backups integration suite — runs against REAL MinIO (the test
 * compose override publishes it on 127.0.0.1:19000) so presigned PUT/GET URLs
 * are exercised end-to-end, not mocked.
 *
 *   docker compose -f docker-compose.yml -f docker-compose.test.yml \
 *     up -d postgres migrate minio
 *   npm run test:e2e
 */
describe('Storage (e2e)', () => {
  let app: NestExpressApplication;
  let database: DatabaseService;
  let minio: MinioService;
  let cleanup: CleanupService;

  const EMAIL = 'frank@example.com';
  const PASSWORD = 'correct-horse-battery-staple';
  const device = randomUUID();

  const fakeMail = {
    enabled: true,
    sendVerification: jest.fn(async () => true),
    sendPasswordReset: jest.fn(async () => true),
  };

  const sha256 = (bytes: Buffer) => createHash('sha256').update(bytes).digest('hex');

  beforeAll(async () => {
    const moduleRef = await Test.createTestingModule({ imports: [AppModule] })
      .overrideProvider(MailService)
      .useValue(fakeMail)
      .compile();

    app = moduleRef.createNestApplication<NestExpressApplication>();
    configureApp(app);
    await app.init();

    database = app.get(DatabaseService);
    minio = app.get(MinioService);
    cleanup = app.get(CleanupService);
    await database.db.execute(
      sql`TRUNCATE TABLE attachments, backups, sync_ops, ledger_entries, transaction_tags,
        app_settings, transactions, accounts, bills, budgets, tags,
        refresh_tokens, devices, users, password_reset_tokens CASCADE`,
    );
  });

  afterAll(async () => {
    await app.close();
  });

  const http = () => request(app.getHttpServer());

  async function login(): Promise<{ token: string }> {
    await http()
      .post('/v1/auth/signup')
      .send({ email: EMAIL, password: PASSWORD })
      .then((res) => {
        if (res.status !== 201 && res.status !== 409) throw new Error('signup failed');
      });
    const res = await http()
      .post('/v1/auth/login')
      .send({ email: EMAIL, password: PASSWORD, deviceId: device, platform: 'web', deviceName: 'Frank Phone' })
      .expect(200);
    return { token: res.body.accessToken };
  }

  let auth: { token: string };

  beforeAll(async () => {
    auth = await login();
  });

  describe('attachments', () => {
    it('creates metadata + a presigned PUT URL, then the client uploads', async () => {
      const body = randomBytes(4096);
      const res = await http()
        .post('/v1/attachments')
        .set('Authorization', `Bearer ${auth.token}`)
        .send({
          mimeType: 'image/jpeg',
          sizeBytes: body.length,
          sha256: sha256(body),
        })
        .expect(201);
      expect(res.body.attachment.id).toBeTruthy();
      expect(res.body.uploadUrl).toContain('http');
      expect(res.body.uploadUrl).toContain('X-Amz-Signature');
      expect(res.body.expiresInSeconds).toBe(900);

      // Upload the blob through the presigned PUT (real network round-trip).
      const put = await fetch(res.body.uploadUrl, {
        method: 'PUT',
        headers: { 'Content-Type': 'image/jpeg' },
        body: body as unknown as BodyInit,
      });
      expect(put.status).toBe(200);

      // Confirm upload.
      await http()
        .patch(`/v1/attachments/${res.body.attachment.id}`)
        .set('Authorization', `Bearer ${auth.token}`)
        .send({ uploaded: true })
        .expect(204);
    });

    it('issues a presigned GET and downloads the same bytes', async () => {
      const list = await database.db.execute(
        sql`SELECT id FROM attachments WHERE user_id IS NOT NULL ORDER BY created_at DESC LIMIT 1`,
      );
      const id = (list.rows[0] as { id: string }).id;

      const urlRes = await http()
        .get(`/v1/attachments/${id}/url`)
        .set('Authorization', `Bearer ${auth.token}`)
        .expect(200);
      expect(urlRes.body.downloadUrl).toContain('X-Amz-Signature');

      const download = await fetch(urlRes.body.downloadUrl);
      expect(download.status).toBe(200);
      const bytes = Buffer.from(await download.arrayBuffer());
      expect(bytes.length).toBe(4096);
    });

    it('rejects confirm when the uploaded object exceeds the declared size', async () => {
      // Declare 10 bytes, upload 1 KB — the presigned PUT cannot bound the
      // upload, so confirm() must stat the object and reject the mismatch.
      const body = randomBytes(1024);
      const res = await http()
        .post('/v1/attachments')
        .set('Authorization', `Bearer ${auth.token}`)
        .send({
          mimeType: 'application/octet-stream',
          sizeBytes: 10,
          sha256: sha256(body),
        })
        .expect(201);
      const put = await fetch(res.body.uploadUrl, {
        method: 'PUT',
        body: body as unknown as BodyInit,
      });
      expect(put.status).toBe(200);

      await http()
        .patch(`/v1/attachments/${res.body.attachment.id}`)
        .set('Authorization', `Bearer ${auth.token}`)
        .send({ uploaded: true })
        .expect(400);

      // The row must NOT be marked uploaded AND the over-limit object must
      // actually be deleted from MinIO (not just left orphaned).
      await http()
        .get(`/v1/attachments/${res.body.attachment.id}/url`)
        .set('Authorization', `Bearer ${auth.token}`)
        .expect(404);
      const row = await database.db.execute(
        sql`SELECT object_key FROM attachments WHERE id = ${res.body.attachment.id}`,
      );
      const objectKey = (row.rows[0] as { object_key: string }).object_key;
      await expect(minio.stat(objectKey)).rejects.toMatchObject({
        code: expect.stringMatching(/NotFound|NoSuchKey/),
      });
    });

    it('404s when confirming an attachment that was never uploaded', async () => {
      const res = await http()
        .post('/v1/attachments')
        .set('Authorization', `Bearer ${auth.token}`)
        .send({
          mimeType: 'application/octet-stream',
          sizeBytes: 64,
          sha256: sha256(randomBytes(64)),
        })
        .expect(201);
      await http()
        .patch(`/v1/attachments/${res.body.attachment.id}`)
        .set('Authorization', `Bearer ${auth.token}`)
        .send({ uploaded: true })
        .expect(404);
    });

    it('404s for another user\'s attachment', async () => {
      const otherEmail = 'grace@example.com';
      await http()
        .post('/v1/auth/signup')
        .send({ email: otherEmail, password: PASSWORD })
        .then((res) => {
          if (res.status !== 201 && res.status !== 409) throw new Error('signup failed');
        });
      const other = await http()
        .post('/v1/auth/login')
        .send({ email: otherEmail, password: PASSWORD, deviceId: randomUUID(), platform: 'web' })
        .expect(200);

      const list = await database.db.execute(
        sql`SELECT id FROM attachments WHERE user_id IS NOT NULL LIMIT 1`,
      );
      const id = (list.rows[0] as { id: string }).id;
      await http()
        .get(`/v1/attachments/${id}/url`)
        .set('Authorization', `Bearer ${other.body.accessToken}`)
        .expect(404);
    });

    it('deletes the attachment (row + object)', async () => {
      const list = await database.db.execute(
        sql`SELECT id FROM attachments WHERE user_id IS NOT NULL LIMIT 1`,
      );
      const id = (list.rows[0] as { id: string }).id;

      await http()
        .delete(`/v1/attachments/${id}`)
        .set('Authorization', `Bearer ${auth.token}`)
        .expect(204);

      await http()
        .get(`/v1/attachments/${id}/url`)
        .set('Authorization', `Bearer ${auth.token}`)
        .expect(404);
    });
  });

  describe('backups', () => {
    it('creates metadata + presigned PUT, uploads, confirms', async () => {
      const body = randomBytes(8192);
      const res = await http()
        .post('/v1/backups')
        .set('Authorization', `Bearer ${auth.token}`)
        .send({ sha256: sha256(body), sizeBytes: body.length, deviceName: 'Frank Phone' })
        .expect(201);
      expect(res.body.backup.id).toBeTruthy();
      expect(res.body.uploadUrl).toContain('X-Amz-Signature');

      const put = await fetch(res.body.uploadUrl, { method: 'PUT', body: body as unknown as BodyInit });
      expect(put.status).toBe(200);

      await http()
        .patch(`/v1/backups/${res.body.backup.id}`)
        .set('Authorization', `Bearer ${auth.token}`)
        .expect(204);
    });

    it('lists backups with the collection contract + device name', async () => {
      const res = await http()
        .get('/v1/backups')
        .set('Authorization', `Bearer ${auth.token}`)
        .expect(200);
      expect(res.body.items).toHaveLength(1);
      expect(res.body.items[0].deviceName).toBe('Frank Phone');
      expect(res.body.total).toBe(1);
    });

    it('downloads the encrypted blob', async () => {
      const list = await database.db.execute(
        sql`SELECT id FROM backups WHERE user_id IS NOT NULL LIMIT 1`,
      );
      const id = (list.rows[0] as { id: string }).id;
      const urlRes = await http()
        .get(`/v1/backups/${id}/url`)
        .set('Authorization', `Bearer ${auth.token}`)
        .expect(200);
      const download = await fetch(urlRes.body.downloadUrl);
      expect(download.status).toBe(200);
      const bytes = Buffer.from(await download.arrayBuffer());
      expect(bytes.length).toBe(8192);
    });

    it('acks restore (client-side decrypt + import)', async () => {
      const list = await database.db.execute(
        sql`SELECT id FROM backups WHERE user_id IS NOT NULL LIMIT 1`,
      );
      const id = (list.rows[0] as { id: string }).id;
      const res = await http()
        .post(`/v1/backups/${id}/restore`)
        .set('Authorization', `Bearer ${auth.token}`)
        .expect(202);
      expect(res.body.status).toBe('accepted');
    });

    it('rejects a backup whose declared size exceeds the policy', async () => {
      return http()
        .post('/v1/backups')
        .set('Authorization', `Bearer ${auth.token}`)
        .send({
          sha256: sha256(randomBytes(8)),
          sizeBytes: 100 * 1024 * 1024 + 1,
        })
        .expect(400);
    });

    it('rejects confirm when the uploaded blob exceeds the declared size', async () => {
      const body = randomBytes(1024);
      const res = await http()
        .post('/v1/backups')
        .set('Authorization', `Bearer ${auth.token}`)
        .send({ sha256: sha256(body), sizeBytes: 5 })
        .expect(201);
      const put = await fetch(res.body.uploadUrl, {
        method: 'PUT',
        body: body as unknown as BodyInit,
      });
      expect(put.status).toBe(200);
      await http()
        .patch(`/v1/backups/${res.body.backup.id}`)
        .set('Authorization', `Bearer ${auth.token}`)
        .expect(400);
    });

    it('prunes the oldest backup past BACKUP_RETENTION', async () => {
      // Retention is 2; create 3 more backups (4 total) — the oldest must go.
      for (let i = 0; i < 3; i++) {
        const body = randomBytes(1024);
        const created = await http()
          .post('/v1/backups')
          .set('Authorization', `Bearer ${auth.token}`)
          .send({ sha256: sha256(body), sizeBytes: body.length })
          .expect(201);
        await fetch(created.body.uploadUrl, { method: 'PUT', body: body as unknown as BodyInit });
        await http()
          .patch(`/v1/backups/${created.body.backup.id}`)
          .set('Authorization', `Bearer ${auth.token}`)
          .expect(204);
      }

      const res = await http()
        .get('/v1/backups')
        .set('Authorization', `Bearer ${auth.token}`)
        .expect(200);
      expect(res.body.items.length).toBeLessThanOrEqual(2);
      expect(res.body.total).toBeLessThanOrEqual(2);
    });
  });

  it('health/ready reports minio when storage is configured', async () => {
    const res = await http().get('/health/ready').expect(200);
    expect(res.body.checks.minio).toBe('up');
  });

  describe('cleanup sweep (Phase 8)', () => {
    it('removes stale unconfirmed attachments + their MinIO objects', async () => {
      // Create metadata (never upload): the row stays unconfirmed.
      const body = randomBytes(2048);
      const res = await http()
        .post('/v1/attachments')
        .set('Authorization', `Bearer ${auth.token}`)
        .send({ mimeType: 'image/png', sizeBytes: body.length, sha256: sha256(body) })
        .expect(201);
      const id = res.body.attachment.id;
      // Actually upload the blob too — the sweep must remove the ORPHANED
      // OBJECT as well as the metadata row (a real client-crash scenario).
      const put = await fetch(res.body.uploadUrl, { method: 'PUT', body: body as unknown as BodyInit });
      expect(put.status).toBe(200);

      // Backdate created_at past the sweep cutoff (default max age 24 h).
      await database.db.execute(
        sql`UPDATE attachments SET created_at = now() - interval '2 days' WHERE id = ${id}`,
      );
      // Capture the object key BEFORE the sweep deletes the metadata row.
      const keyRow = await database.db.execute(
        sql`SELECT object_key FROM attachments WHERE id = ${id}`,
      );
      const objectKey = (keyRow.rows[0] as { object_key: string }).object_key;

      const result = await cleanup.sweep();
      expect(result.attachmentsRemoved).toBeGreaterThanOrEqual(1);

      // Metadata row is gone AND the object is gone from MinIO.
      const row = await database.db.execute(
        sql`SELECT id FROM attachments WHERE id = ${id}`,
      );
      expect(row.rows).toHaveLength(0);
      await expect(minio.stat(objectKey)).rejects.toMatchObject({
        code: expect.stringMatching(/NotFound|NoSuchKey/),
      });
    });

    it('sweeps stale unconfirmed backups too', async () => {
      const body = randomBytes(1024);
      const res = await http()
        .post('/v1/backups')
        .set('Authorization', `Bearer ${auth.token}`)
        .send({ sha256: sha256(body), sizeBytes: body.length })
        .expect(201);
      const id = res.body.backup.id;
      await database.db.execute(
        sql`UPDATE backups SET created_at = now() - interval '3 days' WHERE id = ${id}`,
      );

      const result = await cleanup.sweep();
      expect(result.backupsRemoved).toBeGreaterThanOrEqual(1);
      const row = await database.db.execute(
        sql`SELECT id FROM backups WHERE id = ${id}`,
      );
      expect(row.rows).toHaveLength(0);
    });

    it('leaves fresh unconfirmed uploads alone (within max age)', async () => {
      const res = await http()
        .post('/v1/attachments')
        .set('Authorization', `Bearer ${auth.token}`)
        .send({
          mimeType: 'application/octet-stream',
          sizeBytes: 32,
          sha256: sha256(randomBytes(32)),
        })
        .expect(201);
      const id = res.body.attachment.id;

      const result = await cleanup.sweep();
      // Only the rows backdated above are swept — this fresh one stays.
      const row = await database.db.execute(
        sql`SELECT id FROM attachments WHERE id = ${id}`,
      );
      expect(row.rows).toHaveLength(1);
      expect(result.attachmentsRemoved).toBe(0);
    });
  });
});
