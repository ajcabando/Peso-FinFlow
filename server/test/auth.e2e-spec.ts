// Test environment first — ConfigModule validates at module compile time,
// which happens inside beforeAll (after these assignments run).
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
 * Auth integration suite — runs against REAL PostgreSQL (no fakes for the DB):
 *
 *   docker compose -f docker-compose.yml -f docker-compose.test.yml \
 *     up -d postgres migrate
 *   npm run test:e2e
 *
 * Only MailService is faked (captures tokens instead of sending SMTP).
 */
describe('Auth (e2e)', () => {
  let app: NestExpressApplication;
  let database: DatabaseService;

  const EMAIL = 'ada@example.com';
  const PASSWORD = 'correct-horse-battery-staple';
  const NEW_PASSWORD = 'a-new-stronger-password';
  const device1 = randomUUID();
  const device2 = randomUUID();

  const captured: { kind: 'verification' | 'reset'; email: string; token: string }[] = [];
  const fakeMail = {
    enabled: true,
    sendVerification: jest.fn(async (email: string, token: string) => {
      captured.push({ kind: 'verification', email, token });
      return true;
    }),
    sendPasswordReset: jest.fn(async (email: string, token: string) => {
      captured.push({ kind: 'reset', email, token });
      return true;
    }),
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
      sql`TRUNCATE TABLE refresh_tokens, devices, users, password_reset_tokens CASCADE`,
    );
  });

  afterAll(async () => {
    await app.close();
  });

  const http = () => request(app.getHttpServer());

  describe('signup', () => {
    it('creates an account and sends a verification email', async () => {
      const res = await http()
        .post('/v1/auth/signup')
        .send({ email: EMAIL, password: PASSWORD })
        .expect(201);

      expect(res.body.user.email).toBe(EMAIL);
      expect(res.body.user.isVerified).toBe(false);
      expect(res.body.user.passwordHash).toBeUndefined();
      expect(res.body.verification.sent).toBe(true);
    });

    it('rejects a duplicate email with a CONFLICT envelope', async () => {
      const res = await http()
        .post('/v1/auth/signup')
        .send({ email: EMAIL.toUpperCase(), password: PASSWORD })
        .expect(409);
      expect(res.body.error.code).toBe('CONFLICT');
    });

    it('validates input with a VALIDATION_FAILED envelope', async () => {
      const res = await http()
        .post('/v1/auth/signup')
        .send({ email: 'not-an-email', password: 'short' })
        .expect(400);
      expect(res.body.error.code).toBe('VALIDATION_FAILED');
      expect(Array.isArray(res.body.error.details)).toBe(true);
    });
  });

  describe('email verification', () => {
    it('verifies with the token from the email', async () => {
      const verification = captured.find((m) => m.kind === 'verification');
      expect(verification).toBeDefined();

      await http().post('/v1/auth/verify-email').send({ token: verification!.token }).expect(204);

      const login = await http()
        .post('/v1/auth/login')
        .send({ email: EMAIL, password: PASSWORD, deviceId: device1, platform: 'ios', deviceName: 'Ada iPhone' })
        .expect(200);
      const me = await http()
        .get('/v1/auth/me')
        .set('Authorization', `Bearer ${login.body.accessToken}`)
        .expect(200);
      expect(me.body.user.isVerified).toBe(true);
    });

    it('rejects a bogus verification token', async () => {
      const res = await http()
        .post('/v1/auth/verify-email')
        .send({ token: 'deadbeef' })
        .expect(400);
      expect(res.body.error.code).toBe('VALIDATION_FAILED');
    });
  });

  describe('login + access', () => {
    it('returns tokens and a device record', async () => {
      const res = await http()
        .post('/v1/auth/login')
        .send({ email: EMAIL, password: PASSWORD, deviceId: device1, platform: 'ios', deviceName: 'Ada iPhone' })
        .expect(200);
      expect(res.body.accessToken).toBeTruthy();
      expect(res.body.refreshToken).toBeTruthy();
      expect(res.body.expiresIn).toBe(900);
      expect(res.body.user.email).toBe(EMAIL);
    });

    it('rejects a wrong password with UNAUTHORIZED', async () => {
      const res = await http()
        .post('/v1/auth/login')
        .send({ email: EMAIL, password: 'wrong-password', deviceId: device1, platform: 'ios' })
        .expect(401);
      expect(res.body.error.code).toBe('UNAUTHORIZED');
    });

    it('requires a bearer token for /auth/me', async () => {
      const res = await http().get('/v1/auth/me').expect(401);
      expect(res.body.error.code).toBe('UNAUTHORIZED');
    });

    it('reports the current device in /auth/me', async () => {
      const login = await http()
        .post('/v1/auth/login')
        .send({ email: EMAIL, password: PASSWORD, deviceId: device1, platform: 'ios', deviceName: 'Ada iPhone' })
        .expect(200);
      const me = await http()
        .get('/v1/auth/me')
        .set('Authorization', `Bearer ${login.body.accessToken}`)
        .expect(200);
      expect(me.body.device.id).toBe(device1);
      expect(me.body.device.current).toBe(true);
      expect(me.body.device.platform).toBe('ios');
    });
  });

  describe('refresh token rotation', () => {
    it('rotates on use and rejects reuse (chain revocation)', async () => {
      const login = await http()
        .post('/v1/auth/login')
        .send({ email: EMAIL, password: PASSWORD, deviceId: device1, platform: 'ios' })
        .expect(200);
      const first = login.body.refreshToken;

      const rotated = await http().post('/v1/auth/refresh').send({ refreshToken: first }).expect(200);
      expect(rotated.body.refreshToken).not.toBe(first);
      expect(rotated.body.accessToken).toBeTruthy();

      // Reusing the rotated-away token is treated as theft → whole device dies.
      const reuse = await http().post('/v1/auth/refresh').send({ refreshToken: first }).expect(401);
      expect(reuse.body.error.code).toBe('UNAUTHORIZED');

      // The new token (same device) is now dead too.
      await http().post('/v1/auth/refresh').send({ refreshToken: rotated.body.refreshToken }).expect(401);
    });

    it('rejects an unknown refresh token', async () => {
      const res = await http()
        .post('/v1/auth/refresh')
        .send({ refreshToken: 'definitely-not-a-real-token' })
        .expect(401);
      expect(res.body.error.code).toBe('UNAUTHORIZED');
    });

    it('never issues two valid successors for one token (concurrent rotation)', async () => {
      const login = await http()
        .post('/v1/auth/login')
        .send({ email: EMAIL, password: PASSWORD, deviceId: device1, platform: 'ios' })
        .expect(200);
      const token = login.body.refreshToken;

      const [a, b] = await Promise.all([
        http().post('/v1/auth/refresh').send({ refreshToken: token }),
        http().post('/v1/auth/refresh').send({ refreshToken: token }),
      ]);
      const codes = [a.status, b.status].sort();
      expect(codes).toEqual([200, 401]);

      // The survivor must be a single, valid token.
      const survivor = a.status === 200 ? a.body.refreshToken : b.body.refreshToken;
      const next = await http().post('/v1/auth/refresh').send({ refreshToken: survivor });
      // The chain-revoked device refuses further rotations.
      expect(next.status).toBe(401);
    });

    it('rejects a refresh from a revoked device', async () => {
      const login2 = await http()
        .post('/v1/auth/login')
        .send({ email: EMAIL, password: PASSWORD, deviceId: device2, platform: 'android' })
        .expect(200);
      const login1 = await http()
        .post('/v1/auth/login')
        .send({ email: EMAIL, password: PASSWORD, deviceId: device1, platform: 'ios' })
        .expect(200);

      await http()
        .delete(`/v1/devices/${device2}`)
        .set('Authorization', `Bearer ${login1.body.accessToken}`)
        .expect(204);

      const res = await http()
        .post('/v1/auth/refresh')
        .send({ refreshToken: login2.body.refreshToken })
        .expect(401);
      expect(res.body.error.code).toBe('UNAUTHORIZED');
    });
  });

  describe('logout', () => {
    it('revokes the presented refresh token', async () => {
      const login = await http()
        .post('/v1/auth/login')
        .send({ email: EMAIL, password: PASSWORD, deviceId: device1, platform: 'ios' })
        .expect(200);

      await http()
        .post('/v1/auth/logout')
        .set('Authorization', `Bearer ${login.body.accessToken}`)
        .send({ refreshToken: login.body.refreshToken })
        .expect(204);

      await http().post('/v1/auth/refresh').send({ refreshToken: login.body.refreshToken }).expect(401);
    });
  });

  describe('devices', () => {
    it('lists devices and revokes another install (not the current one)', async () => {
      // device1 is logged in and current; device2 is a second install.
      const login1 = await http()
        .post('/v1/auth/login')
        .send({ email: EMAIL, password: PASSWORD, deviceId: device1, platform: 'ios', deviceName: 'Ada iPhone' })
        .expect(200);
      await http()
        .post('/v1/auth/login')
        .send({ email: EMAIL, password: PASSWORD, deviceId: device2, platform: 'android', deviceName: 'Ada Pixel' })
        .expect(200);

      const list = await http()
        .get('/v1/devices')
        .set('Authorization', `Bearer ${login1.body.accessToken}`)
        .expect(200);
      expect(list.body.devices).toHaveLength(2);
      const current = list.body.devices.find((d: { id: string }) => d.id === device1);
      expect(current.current).toBe(true);

      await http()
        .delete(`/v1/devices/${device2}`)
        .set('Authorization', `Bearer ${login1.body.accessToken}`)
        .expect(204);

      const after = await http()
        .get('/v1/devices')
        .set('Authorization', `Bearer ${login1.body.accessToken}`)
        .expect(200);
      const revoked = after.body.devices.find((d: { id: string }) => d.id === device2);
      expect(revoked.revokedAt).toBeTruthy();

      // Revoking the CURRENT device via the endpoint is refused.
      const refused = await http()
        .delete(`/v1/devices/${device1}`)
        .set('Authorization', `Bearer ${login1.body.accessToken}`)
        .expect(400);
      expect(refused.body.error.code).toBe('VALIDATION_FAILED');
    });

    it('never lets one user revoke another user\'s device (404, scoped)', async () => {
      // Bob signs up + logs in on his own install.
      const bobEmail = 'bob@example.com';
      const bobDevice = randomUUID();
      await http()
        .post('/v1/auth/signup')
        .send({ email: bobEmail, password: PASSWORD })
        .expect(201);
      const bobLogin = await http()
        .post('/v1/auth/login')
        .send({ email: bobEmail, password: PASSWORD, deviceId: bobDevice, platform: 'web' })
        .expect(200);

      // Ada (device1, still logged in) tries to revoke Bob's install.
      const adaLogin = await http()
        .post('/v1/auth/login')
        .send({ email: EMAIL, password: PASSWORD, deviceId: device1, platform: 'ios' })
        .expect(200);
      const res = await http()
        .delete(`/v1/devices/${bobDevice}`)
        .set('Authorization', `Bearer ${adaLogin.body.accessToken}`)
        .expect(404);
      expect(res.body.error.code).toBe('NOT_FOUND');

      // Bob's session is untouched.
      const bobMe = await http()
        .get('/v1/auth/me')
        .set('Authorization', `Bearer ${bobLogin.body.accessToken}`)
        .expect(200);
      expect(bobMe.body.user.email).toBe(bobEmail);
    });
  });

  describe('password reset', () => {
    it('resets the password and kills all sessions', async () => {
      const requested = await http()
        .post('/v1/auth/password/reset')
        .send({ email: EMAIL })
        .expect(202);
      expect(requested.body.sent).toBe(true);

      const reset = captured.findLast((m) => m.kind === 'reset');
      expect(reset).toBeDefined();

      await http()
        .post('/v1/auth/password/reset/confirm')
        .send({ token: reset!.token, newPassword: NEW_PASSWORD })
        .expect(204);

      // Old password fails, new password works.
      await http()
        .post('/v1/auth/login')
        .send({ email: EMAIL, password: PASSWORD, deviceId: device1, platform: 'ios' })
        .expect(401);
      const relogin = await http()
        .post('/v1/auth/login')
        .send({ email: EMAIL, password: NEW_PASSWORD, deviceId: device1, platform: 'ios' })
        .expect(200);
      expect(relogin.body.accessToken).toBeTruthy();
    });

    it('does not reveal whether an email exists (same response, nothing sent)', async () => {
      const before = captured.length;
      const res = await http()
        .post('/v1/auth/password/reset')
        .send({ email: 'nobody@example.com' })
        .expect(202);
      // Same `sent` value as a real account request, and no email was queued.
      expect(res.body.sent).toBe(true);
      expect(captured.length).toBe(before);
    });

    it('rejects an invalid reset token', async () => {
      const res = await http()
        .post('/v1/auth/password/reset/confirm')
        .send({ token: 'bogus', newPassword: NEW_PASSWORD })
        .expect(400);
      expect(res.body.error.code).toBe('VALIDATION_FAILED');
    });

    it('invalidates an older reset token when a new one is requested', async () => {
      const before = captured.length;

      // First request issues a token; second request must kill it.
      await http().post('/v1/auth/password/reset').send({ email: EMAIL }).expect(202);
      await http().post('/v1/auth/password/reset').send({ email: EMAIL }).expect(202);

      const resets = captured.slice(before).filter((m) => m.kind === 'reset');
      expect(resets).toHaveLength(2);

      // The FIRST (now superseded) token must be rejected.
      const stale = await http()
        .post('/v1/auth/password/reset/confirm')
        .send({ token: resets[0].token, newPassword: NEW_PASSWORD })
        .expect(400);
      expect(stale.body.error.code).toBe('VALIDATION_FAILED');

      // The NEWEST token still works (the older one's invalidation must not
      // have nuked it).
      await http()
        .post('/v1/auth/password/reset/confirm')
        .send({ token: resets[1].token, newPassword: NEW_PASSWORD })
        .expect(204);
    });
  });
});
