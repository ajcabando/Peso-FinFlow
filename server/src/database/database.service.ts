import { Injectable, Logger, OnModuleDestroy } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { drizzle, NodePgDatabase } from 'drizzle-orm/node-postgres';
import { Pool } from 'pg';
import * as schema from '../drizzle/schema';

/**
 * Owns the PostgreSQL connection pool and the Drizzle client. The pool is
 * lazy — no connection is opened until the first query, so the API boots even
 * if the database is briefly unreachable (health checks surface that).
 */
@Injectable()
export class DatabaseService implements OnModuleDestroy {
  private readonly logger = new Logger(DatabaseService.name);
  private readonly pool: Pool;
  readonly db: NodePgDatabase<typeof schema>;

  constructor(config: ConfigService) {
    this.pool = new Pool({
      connectionString: config.getOrThrow<string>('DATABASE_URL'),
      max: 10,
      // Fail fast instead of letting /health/ready hang on a dead database.
      connectionTimeoutMillis: 5000,
      idleTimeoutMillis: 30000,
    });
    this.pool.on('error', (error) => {
      // Idle-client errors must not crash the process.
      this.logger.error(`Unexpected pool error: ${error.message}`);
    });
    this.db = drizzle(this.pool, { schema });
  }

  /** Trivial round-trip used by /health/ready. */
  async ping(): Promise<void> {
    const client = await this.pool.connect();
    try {
      await client.query('SELECT 1');
    } finally {
      client.release();
    }
  }

  async onModuleDestroy(): Promise<void> {
    await this.pool.end();
  }
}
