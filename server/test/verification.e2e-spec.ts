// Runs the strict verification path: EMAIL_VERIFICATION_REQUIRED=true, so
// accounts cannot log in until their email is verified. Same real-DB setup as
// auth.e2e-spec.ts (see that file's header for the compose command).
process.env.NODE_ENV = 'test';
process.env.DATABASE_URL ??= 'postgres://finflow:finflow-dev-pass@127.0.0.1:54321/finflow';
process.env.JWT_ACCESS_SECRET ??= 'e2e-test-secret-0123456789abcdef0123456789abcdef';
process.env.THROTTLE_LIMIT = '10000';
process.env.AUTH_MAX_ATTEMPTS_PER_MINUTE = '10000';
process.env.AUTH_MAX_FAILURES_PER_HOUR = '10000';
// Boot-time cross-field validation requires SMTP when verification is on.
process.env.EMAIL_VERIFICATION_REQUIRED = 'true';
process.env.SMTP_HOST = 'smtp.test';
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

describe('Email verification required (e2e)', () => {
  let app: NestExpressApplication;

  const EMAIL = 'verified@example.com';
  const PASSWORD = 'correct-horse-battery';
  const deviceId = randomUUID();

  const captured: { kind: 'verification'; email: string; token: string }[] = [];
  const fakeMail = {
    enabled: true,
    sendVerification: jest.fn(async (email: string, token: string) => {
      captured.push({ kind: 'verification', email, token });
      return true;
    }),
    sendPasswordReset: jest.fn(async () => false),
  };

  beforeAll(async () => {
    const moduleRef = await Test.createTestingModule({ imports: [AppModule] })
      .overrideProvider(MailService)
      .useValue(fakeMail)
      .compile();

    app = moduleRef.createNestApplication<NestExpressApplication>();
    configureApp(app);
    await app.init();

    const database = app.get(DatabaseService);
    await database.db.execute(
      sql`TRUNCATE TABLE refresh_tokens, devices, users, password_reset_tokens CASCADE`,
    );
  });

  afterAll(async () => {
    await app.close();
  });

  const http = () => request(app.getHttpServer());
  const login = () =>
    http().post('/v1/auth/login').send({
      email: EMAIL,
      password: PASSWORD,
      deviceId,
      platform: 'ios',
    });

  it('blocks login before verification (403 FORBIDDEN)', async () => {
    await http()
      .post('/v1/auth/signup')
      .send({ email: EMAIL, password: PASSWORD })
      .expect(201);

    const res = await login().expect(403);
    expect(res.body.error.code).toBe('FORBIDDEN');
  });

  it('verifies with the emailed token and then allows login', async () => {
    const verification = captured.find((m) => m.kind === 'verification');
    expect(verification).toBeDefined();

    await http()
      .post('/v1/auth/verify-email')
      .send({ token: verification!.token })
      .expect(204);

    const res = await login().expect(200);
    expect(res.body.user.isVerified).toBe(true);
    expect(res.body.accessToken).toBeTruthy();
  });

  it('cannot log in after a failed verification attempt', async () => {
    // A second unverified account.
    const other = `other-${randomUUID()}@example.com`;
    await http()
      .post('/v1/auth/signup')
      .send({ email: other, password: PASSWORD })
      .expect(201);

    await http().post('/v1/auth/verify-email').send({ token: 'bogus-token' }).expect(400);

    const res = await http()
      .post('/v1/auth/login')
      .send({ email: other, password: PASSWORD, deviceId: randomUUID(), platform: 'web' })
      .expect(403);
    expect(res.body.error.code).toBe('FORBIDDEN');
  });
});
