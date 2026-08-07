import { ConfigService } from '@nestjs/config';
import { HttpException } from '@nestjs/common';
import { LoginAttemptsService } from './login-attempts.service';
import { RedisService } from '../redis/redis.service';

async function expect429(promise: Promise<void>) {
  try {
    await promise;
    throw new Error('expected assertAllowed to throw');
  } catch (error) {
    expect(error).toBeInstanceOf(HttpException);
    expect((error as HttpException).getStatus()).toBe(429);
  }
}

/** RedisService with enabled=true and jest-fn counters (no real connection). */
function fakeRedis(): RedisService {
  const redis = {
    enabled: true,
    client: {},
    get: jest.fn(async () => 0),
    incr: jest.fn(async () => 1),
    del: jest.fn(async () => undefined),
  } as unknown as RedisService;
  return redis;
}

function buildService(overrides: Record<string, string>, redis?: RedisService) {
  return new LoginAttemptsService(new ConfigService(overrides), redis ?? fakeDisabledRedis());
}

function fakeDisabledRedis(): RedisService {
  return { enabled: false } as unknown as RedisService;
}

describe('LoginAttemptsService (in-memory fallback)', () => {
  beforeEach(() => {
    jest.useFakeTimers();
  });
  afterEach(() => {
    jest.useRealTimers();
  });

  it('allows attempts below the per-IP limit', async () => {
    const service = buildService({ AUTH_MAX_ATTEMPTS_PER_MINUTE: '3' });
    await service.recordFailure('a@x.io', '1.2.3.4');
    await service.recordFailure('a@x.io', '1.2.3.4');
    await expect(service.assertAllowed('a@x.io', '1.2.3.4')).resolves.toBeUndefined();
  });

  it('blocks the 4th attempt from the same IP within a minute', async () => {
    const service = buildService({ AUTH_MAX_ATTEMPTS_PER_MINUTE: '3' });
    for (let i = 0; i < 3; i++) await service.recordFailure('a@x.io', '1.2.3.4');
    await expect429(service.assertAllowed('a@x.io', '1.2.3.4'));
  });

  it('releases the IP block after the window lapses', async () => {
    const service = buildService({ AUTH_MAX_ATTEMPTS_PER_MINUTE: '2' });
    await service.recordFailure('a@x.io', '1.2.3.4');
    await service.recordFailure('a@x.io', '1.2.3.4');
    await expect429(service.assertAllowed('a@x.io', '1.2.3.4'));
    jest.advanceTimersByTime(61_000);
    await expect(service.assertAllowed('a@x.io', '1.2.3.4')).resolves.toBeUndefined();
  });

  it('blocks per-email after AUTH_MAX_FAILURES_PER_HOUR failures', async () => {
    const service = buildService({ AUTH_MAX_FAILURES_PER_HOUR: '2' });
    await service.recordFailure('victim@x.io', '9.9.9.9');
    await service.recordFailure('victim@x.io', '8.8.8.8'); // different IP, same email
    await expect429(service.assertAllowed('victim@x.io', '7.7.7.7'));
  });

  it('resets the email counter on success', async () => {
    const service = buildService({ AUTH_MAX_FAILURES_PER_HOUR: '1' });
    await service.recordFailure('victim@x.io', '9.9.9.9');
    await service.recordSuccess('victim@x.io');
    await expect(service.assertAllowed('victim@x.io', '9.9.9.9')).resolves.toBeUndefined();
  });
});

describe('LoginAttemptsService (Redis-backed)', () => {
  it('reads shared counters from Redis and blocks when the email limit is hit', async () => {
    const redis = fakeRedis();
    (redis.get as jest.Mock).mockImplementation(async (key: string) =>
      key.startsWith('auth:fail:') ? 10 : 1,
    );
    const service = buildService({ AUTH_MAX_FAILURES_PER_HOUR: '5' }, redis);
    await expect429(service.assertAllowed('victim@x.io', '1.2.3.4'));
  });

  it('records failures as INCRs with a TTL window', async () => {
    const redis = fakeRedis();
    const service = buildService({ AUTH_MAX_ATTEMPTS_PER_MINUTE: '5' }, redis);
    await service.recordFailure('a@x.io', '1.2.3.4');
    expect(redis.incr).toHaveBeenCalledTimes(2);
    expect(redis.incr).toHaveBeenCalledWith('auth:fail:a@x.io', 3600);
    expect(redis.incr).toHaveBeenCalledWith('auth:ip:1.2.3.4', 60);
  });

  it('is fail-open when Redis reads error (counter treated as 0)', async () => {
    const redis = fakeRedis();
    (redis.get as jest.Mock).mockRejectedValue(new Error('redis down'));
    const service = buildService({ AUTH_MAX_FAILURES_PER_HOUR: '1' }, redis);
    await expect(service.assertAllowed('victim@x.io', '1.2.3.4')).resolves.toBeUndefined();
  });

  it('clears the email counter on success', async () => {
    const redis = fakeRedis();
    const service = buildService({ AUTH_MAX_FAILURES_PER_HOUR: '5' }, redis);
    await service.recordSuccess('victim@x.io');
    expect(redis.del).toHaveBeenCalledWith('auth:fail:victim@x.io');
  });
});
