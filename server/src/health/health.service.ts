import { Injectable, Logger } from '@nestjs/common';
import { DatabaseService } from '../database/database.service';
import { MinioService } from '../storage/minio.service';
import { RedisService } from '../redis/redis.service';

export interface ReadinessResult {
  status: 'ok' | 'degraded';
  checks: Record<string, 'up' | 'down'>;
}

/**
 * Readiness probe. Each dependency is checked independently so a single
 * failure reports `degraded` with the culprit named, rather than failing
 * everything. MinIO is only checked when storage is configured; Redis only
 * when REDIS_URL is set — both are optional dependencies.
 */
@Injectable()
export class HealthService {
  private readonly logger = new Logger(HealthService.name);

  constructor(
    private readonly database: DatabaseService,
    private readonly minio: MinioService,
    private readonly redis: RedisService,
  ) {}

  async readiness(): Promise<ReadinessResult> {
    const checks: Record<string, 'up' | 'down'> = {};

    try {
      await this.database.ping();
      checks.postgres = 'up';
    } catch (error) {
      checks.postgres = 'down';
      this.logger.warn(`Postgres health check failed: ${String(error)}`);
    }

    if (this.minio.enabled) {
      try {
        await this.minio.ping();
        checks.minio = 'up';
      } catch (error) {
        checks.minio = 'down';
        this.logger.warn(`MinIO health check failed: ${String(error)}`);
      }
    }

    if (this.redis.enabled) {
      try {
        await this.redis.ping();
        checks.redis = 'up';
      } catch (error) {
        checks.redis = 'down';
        this.logger.warn(`Redis health check failed: ${String(error)}`);
      }
    }

    return {
      status: Object.values(checks).every((value) => value === 'up')
        ? 'ok'
        : 'degraded',
      checks,
    };
  }
}
