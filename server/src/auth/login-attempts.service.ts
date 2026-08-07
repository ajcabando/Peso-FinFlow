import { HttpException, HttpStatus, Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { RedisService } from '../redis/redis.service';

interface Bucket {
  count: number;
  windowEnd: number;
}

/**
 * Brute-force protection on top of the global throttler:
 *  - per IP:        AUTH_MAX_ATTEMPTS_PER_MINUTE (default 5/min) — all attempts
 *  - per email:     AUTH_MAX_FAILURES_PER_HOUR (default 10/hour) — failures only
 *
 * Counters live in Redis (shared across instances) when REDIS_URL is set, and
 * fall back to identical in-process maps otherwise. Redis failures are
 * fail-open: a counter read error counts as 0 (an outage must never lock every
 * user out), and write errors are swallowed.
 */
@Injectable()
export class LoginAttemptsService {
  private readonly byEmail = new Map<string, Bucket>();
  private readonly byIp = new Map<string, Bucket>();

  private readonly ipLimit: number;
  private readonly ipWindowMs = 60_000;
  private readonly emailLimit: number;
  private readonly emailWindowMs = 3_600_000;

  constructor(
    config: ConfigService,
    private readonly redis: RedisService,
  ) {
    this.ipLimit = config.get<number>('AUTH_MAX_ATTEMPTS_PER_MINUTE', 5);
    this.emailLimit = config.get<number>('AUTH_MAX_FAILURES_PER_HOUR', 10);
  }

  /** Throws a 429 (mapped to TOO_MANY_REQUESTS) when a counter is exhausted. */
  async assertAllowed(email: string, ip: string): Promise<void> {
    if (this.redis.enabled) {
      const [emailCount, ipCount] = await Promise.all([
        this.redis.get(this.emailKey(email)).catch(() => 0),
        this.redis.get(this.ipKey(ip)).catch(() => 0),
      ]);
      if ((emailCount ?? 0) >= this.emailLimit) {
        throw new HttpException(
          'Too many failed attempts for this email — try again in an hour',
          HttpStatus.TOO_MANY_REQUESTS,
        );
      }
      if ((ipCount ?? 0) >= this.ipLimit) {
        throw new HttpException(
          'Too many attempts from this device — try again in a minute',
          HttpStatus.TOO_MANY_REQUESTS,
        );
      }
      return;
    }

    if (this.exhausted(this.byEmail.get(this.emailKey(email)), this.emailLimit)) {
      throw new HttpException(
        'Too many failed attempts for this email — try again in an hour',
        HttpStatus.TOO_MANY_REQUESTS,
      );
    }
    if (this.exhausted(this.byIp.get(ip), this.ipLimit)) {
      throw new HttpException(
        'Too many attempts from this device — try again in a minute',
        HttpStatus.TOO_MANY_REQUESTS,
      );
    }
  }

  async recordFailure(email: string, ip: string): Promise<void> {
    if (this.redis.enabled) {
      await Promise.all([
        this.redis.incr(this.emailKey(email), this.emailWindowMs / 1000).catch(() => undefined),
        this.redis.incr(this.ipKey(ip), this.ipWindowMs / 1000).catch(() => undefined),
      ]);
      return;
    }
    this.bump(this.byEmail, this.emailKey(email), this.emailWindowMs);
    this.bump(this.byIp, ip, this.ipWindowMs);
  }

  async recordSuccess(email: string): Promise<void> {
    if (this.redis.enabled) {
      await this.redis.del(this.emailKey(email)).catch(() => undefined);
      return;
    }
    this.byEmail.delete(this.emailKey(email));
  }

  private exhausted(bucket: Bucket | undefined, limit: number): boolean {
    if (!bucket) return false;
    if (Date.now() >= bucket.windowEnd) return false; // window lapsed
    return bucket.count >= limit;
  }

  private bump(
    map: Map<string, Bucket>,
    key: string,
    windowMs: number,
  ): void {
    const now = Date.now();
    const existing = map.get(key);
    if (!existing || now >= existing.windowEnd) {
      map.set(key, { count: 1, windowEnd: now + windowMs });
    } else {
      existing.count += 1;
    }
  }

  private emailKey(email: string): string {
    return `auth:fail:${email.toLowerCase().trim()}`;
  }

  private ipKey(ip: string): string {
    return `auth:ip:${ip}`;
  }
}
