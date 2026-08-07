// Test environment first — ConfigModule validates at module compile time,
// which happens inside beforeAll (after these assignments run).
process.env.NODE_ENV = 'test';
process.env.DATABASE_URL ??= 'postgres://finflow:test@localhost:5432/finflow_test';
process.env.JWT_ACCESS_SECRET ??= 'e2e-test-secret-0123456789abcdef0123456789abcdef';
process.env.THROTTLE_LIMIT = '1000';
process.env.LOG_LEVEL = 'silent';
process.env.REDIS_URL = '';
process.env.MINIO_ENDPOINT = ''; // storage disabled in non-storage suites // tests use the in-memory limiter (no docker-internal host)

import { Test } from '@nestjs/testing';
import { NestExpressApplication } from '@nestjs/platform-express';
import request from 'supertest';
import { configureApp } from '../src/app.setup';
import { AppModule } from '../src/app.module';
import { DatabaseService } from '../src/database/database.service';

/**
 * Boots the real AppModule (filters, pipes, throttler, logging — everything)
 * with only the database faked, so these tests need no PostgreSQL.
 */
describe('Health & error envelope (e2e)', () => {
  let app: NestExpressApplication;

  const fakeDatabase = {
    ping: jest.fn(async () => undefined),
  };

  beforeAll(async () => {
    const moduleRef = await Test.createTestingModule({ imports: [AppModule] })
      .overrideProvider(DatabaseService)
      .useValue(fakeDatabase)
      .compile();

    app = moduleRef.createNestApplication<NestExpressApplication>();
    // Mirror main.ts (global prefix + body limits from the shared setup).
    configureApp(app);
    await app.init();
  });

  afterAll(async () => {
    await app.close();
  });

  describe('GET /health', () => {
    it('reports ok with uptime', async () => {
      const res = await request(app.getHttpServer()).get('/health').expect(200);
      expect(res.body.status).toBe('ok');
      expect(typeof res.body.uptimeSeconds).toBe('number');
    });
  });

  describe('GET /health/ready', () => {
    it('returns 200 with postgres up when the database responds', async () => {
      const res = await request(app.getHttpServer()).get('/health/ready').expect(200);
      expect(res.body.status).toBe('ok');
      expect(res.body.checks.postgres).toBe('up');
    });

    it('returns 503 degraded (with checks, not the error envelope) when the database is down', async () => {
      fakeDatabase.ping.mockRejectedValueOnce(new Error('connection refused'));
      const res = await request(app.getHttpServer()).get('/health/ready').expect(503);
      expect(res.body.status).toBe('degraded');
      expect(res.body.checks.postgres).toBe('down');
    });
  });

  describe('error envelope', () => {
    it('returns the uniform envelope for an unknown route', async () => {
      const res = await request(app.getHttpServer()).get('/v1/nope').expect(404);
      expect(res.body.error.code).toBe('NOT_FOUND');
      expect(res.body.error.requestId).toBeTruthy();
    });

    it('does not put /health under the /v1 prefix', async () => {
      const res = await request(app.getHttpServer()).get('/v1/health').expect(404);
      expect(res.body.error.code).toBe('NOT_FOUND');
    });
  });
});
