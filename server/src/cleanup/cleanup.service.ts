import { Injectable, Logger, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { and, eq, isNull, lt } from 'drizzle-orm';
import { attachments, backups } from '../drizzle/schema';
import { DatabaseService } from '../database/database.service';
import { MinioService } from '../storage/minio.service';

/**
 * Storage-DoS cleanup sweep (Phase 8, docs/SELF_HOSTED.md §5).
 *
 * A presigned PUT can be issued and never confirmed (client crash, aborted
 * upload, abuse) — the confirm-time `statObject` check closes the size lie,
 * but rows with `uploaded_at IS NULL` would otherwise accumulate forever and,
 * when the blob WAS uploaded but never confirmed, orphan objects in MinIO.
 *
 * This service sweeps both: rows older than `STORAGE_CLEANUP_MAX_AGE_HOURS`
 * (default 24 h) that were never confirmed are removed along with their
 * MinIO objects. Runs on `STORAGE_CLEANUP_INTERVAL_SECONDS` (default 6 h)
 * after a short boot grace. Disabled when MinIO is not configured.
 */
@Injectable()
export class CleanupService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(CleanupService.name);
  private timer: NodeJS.Timeout | null = null;
  private readonly enabled: boolean;
  private readonly intervalMs: number;
  private readonly maxAgeMs: number;

  constructor(
    private readonly database: DatabaseService,
    private readonly minio: MinioService,
    config: ConfigService,
  ) {
    this.enabled = config.get<boolean>('STORAGE_CLEANUP_ENABLED', true);
    this.intervalMs =
      config.get<number>('STORAGE_CLEANUP_INTERVAL_SECONDS', 6 * 3600) * 1000;
    this.maxAgeMs =
      config.get<number>('STORAGE_CLEANUP_MAX_AGE_HOURS', 24) * 3600 * 1000;
  }

  onModuleInit(): void {
    if (!this.enabled || !this.minio.enabled) {
      this.logger.log(
        'Cleanup sweep disabled (STORAGE_CLEANUP_ENABLED=false or MinIO not configured)',
      );
      return;
    }
    // Boot grace so migrations + health checks finish first; then the interval.
    this.timer = setTimeout(() => {
      void this.runSweep();
      this.timer = setInterval(() => void this.runSweep(), this.intervalMs);
      this.timer.unref?.();
    }, 60_000);
  }

  /**
   * Deletes stale unconfirmed uploads. Idempotent — safe to call on demand
   * (the e2e suite drives it directly) and on the interval.
   */
  async sweep(): Promise<{ attachmentsRemoved: number; backupsRemoved: number }> {
    const cutoff = new Date(Date.now() - this.maxAgeMs);
    const db = this.database.db;

    const staleAttachments = await db
      .select()
      .from(attachments)
      .where(and(isNull(attachments.uploadedAt), lt(attachments.createdAt, cutoff)));
    for (const row of staleAttachments) {
      await this.minio.remove(row.objectKey);
      await db
        .delete(attachments)
        .where(and(eq(attachments.userId, row.userId), eq(attachments.id, row.id)));
      this.logger.warn(
        `Swept unconfirmed attachment ${row.id} (created ${row.createdAt.toISOString()})`,
      );
    }

    const staleBackups = await db
      .select()
      .from(backups)
      .where(and(isNull(backups.uploadedAt), lt(backups.createdAt, cutoff)));
    for (const row of staleBackups) {
      await this.minio.remove(row.objectKey);
      await db
        .delete(backups)
        .where(and(eq(backups.userId, row.userId), eq(backups.id, row.id)));
      this.logger.warn(
        `Swept unconfirmed backup ${row.id} (created ${row.createdAt.toISOString()})`,
      );
    }

    if (staleAttachments.length > 0 || staleBackups.length > 0) {
      this.logger.log(
        `Cleanup sweep: removed ${staleAttachments.length} unconfirmed ` +
          `attachment(s), ${staleBackups.length} unconfirmed backup(s)`,
      );
    }
    return {
      attachmentsRemoved: staleAttachments.length,
      backupsRemoved: staleBackups.length,
    };
  }

  onModuleDestroy(): void {
    if (this.timer) clearTimeout(this.timer);
  }

  private runSweep(): void {
    void this.sweep().catch((error) =>
      this.logger.error(`Cleanup sweep failed: ${String(error)}`),
    );
  }
}
