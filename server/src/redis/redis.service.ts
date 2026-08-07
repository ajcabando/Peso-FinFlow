import { Injectable, Logger, OnModuleDestroy } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import Redis from 'ioredis';

/**
 * Optional Redis client. When `REDIS_URL` is empty (env default) the service
 * reports `disabled` and callers fall back to their in-process behaviour —
 * the app is fully functional without Redis (the brute-force limiter just
 * isn't shared across instances). Health checks report redis: down.
 */
@Injectable()
export class RedisService implements OnModuleDestroy {
  private readonly logger = new Logger(RedisService.name);
  readonly client: Redis | null;

  constructor(config: ConfigService) {
    const url = config.get<string>('REDIS_URL', '');
    if (!url) {
      this.logger.warn('REDIS_URL is empty — Redis disabled (in-memory fallbacks active)');
      this.client = null;
      return;
    }
    this.client = new Redis(url, {
      maxRetriesPerRequest: 2,
      lazyConnect: true, // don't block boot — health checks surface outages
      enableOfflineQueue: false,
    });
    // Never crash the process on a dead Redis — the limiter treats errors as
    // "allow" (fail-open) rather than locking everyone out.
    this.client.on('error', (error) => {
      this.logger.error(`Redis error: ${error.message}`);
    });
    // lazyConnect defers the TCP connect until an explicit call — do it in
    // the background now (errors are logged, never fatal). Commands issued
    // before the link is up fail fast (enableOfflineQueue: false).
    void this.client.connect().catch((error) => {
      this.logger.error(`Redis connect failed: ${error.message}`);
    });
  }

  get enabled(): boolean {
    return this.client !== null;
  }

  /**
   * Health probe with a hard timeout — a dead/unreachable Redis must degrade
   * /health/ready, not hang it (ioredis keeps retrying the connect forever).
   */
  async ping(): Promise<void> {
    if (!this.client) throw new Error('Redis disabled');
    let timeout: ReturnType<typeof setTimeout> | undefined;
    try {
      await Promise.race([
        this.client.ping(),
        new Promise((_, reject) => {
          timeout = setTimeout(
            () => reject(new Error('Redis ping timed out')),
            2000,
          );
        }),
      ]);
    } finally {
      clearTimeout(timeout);
    }
  }

  /**
   * Reads a counter (null when absent/expired). Non-numeric values are
   * treated as absent rather than NaN — a garbage value must never disable
   * the limiter with a NaN comparison.
   */
  async get(key: string): Promise<number | null> {
    if (!this.client) throw new Error('Redis disabled');
    const value = await this.client.get(key);
    if (value === null) return null;
    const count = Number(value);
    return Number.isFinite(count) ? count : null;
  }

  /**
   * INCR with expiry — atomic counter. EXPIRE runs unconditionally in the
   * same pipeline (an existing key without TTL would otherwise never expire).
   */
  async incr(key: string, windowSeconds: number): Promise<number> {
    if (!this.client) throw new Error('Redis disabled');
    const pipeline = this.client.pipeline();
    pipeline.incr(key);
    pipeline.expire(key, windowSeconds);
    const results = await pipeline.exec();
    const count = results?.[0]?.[1] as number | null;
    return count ?? 0;
  }

  async del(key: string): Promise<void> {
    await this.client?.del(key);
  }

  async onModuleDestroy(): Promise<void> {
    await this.client?.quit().catch(() => undefined);
  }
}
