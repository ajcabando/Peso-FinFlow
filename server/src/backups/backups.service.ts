import {
  BadRequestException,
  Injectable,
  NotFoundException,
  ServiceUnavailableException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { and, asc, count, desc, eq } from 'drizzle-orm';
import { randomUUID } from 'node:crypto';
import { DatabaseService } from '../database/database.service';
import { backups, devices } from '../drizzle/schema';
import { MinioService } from '../storage/minio.service';
import { CreateBackupDto } from './backup.dto';

const PUT_TTL_SECONDS = 900;
const GET_TTL_SECONDS = 3600;

export interface BackupView {
  id: string;
  deviceId: string | null;
  deviceName: string | null;
  sizeBytes: number;
  sha256: string;
  uploadedAt: Date | null;
  createdAt: Date;
}

@Injectable()
export class BackupsService {
  private readonly retention: number;
  private readonly maxBytes: number;

  constructor(
    private readonly database: DatabaseService,
    private readonly minio: MinioService,
    config: ConfigService,
  ) {
    this.retention = config.get<number>('BACKUP_RETENTION', 10);
    this.maxBytes = config.get<number>('MAX_BACKUP_BYTES', 100 * 1024 * 1024);
  }

  /**
   * Two-step like attachments: create metadata + presigned PUT, client uploads
   * the client-encrypted blob, then PATCHes { uploaded: true }. The server is
   * zero-knowledge — the payload never transits the API body.
   */
  async create(
    userId: string,
    deviceId: string,
    dto: CreateBackupDto,
  ): Promise<{ backup: BackupView; uploadUrl: string; expiresInSeconds: number }> {
    if (!this.minio.enabled) {
      throw new ServiceUnavailableException('Object storage is not configured');
    }
    // Declared-size policy (the actual object is verified at confirm time).
    if (dto.sizeBytes > this.maxBytes) {
      throw new BadRequestException(
        `Backup exceeds the ${this.maxBytes} byte limit`,
      );
    }
    const id = randomUUID();
    const objectKey = `backups/${userId}/${id}`;
    await this.database.db.insert(backups).values({
      id,
      userId,
      deviceId,
      objectKey,
      sizeBytes: dto.sizeBytes,
      sha256: dto.sha256,
    });
    const uploadUrl = await this.minio.presignedPut(objectKey, PUT_TTL_SECONDS);
    const [row] = await this.requireRow(userId, id);
    return { backup: await this.toView(row), uploadUrl, expiresInSeconds: PUT_TTL_SECONDS };
  }

  /**
   * Confirms the upload and prunes the oldest backups past BACKUP_RETENTION.
   * The blob is verified against the declared size before marking it uploaded
   * (a presigned PUT URL cannot bound the upload, so stat is the real check).
   */
  async confirm(userId: string, id: string): Promise<void> {
    const [row] = await this.requireRow(userId, id);
    if (!row.uploadedAt) {
      const actualSize = await this.verifyUploaded(row.objectKey);
      // Reject when the blob exceeds EITHER the declared size OR the policy
      // cap — declaring a tiny size must not bypass the limit.
      const cap = Math.min(row.sizeBytes, this.maxBytes);
      if (actualSize > cap) {
        await this.minio.remove(row.objectKey);
        throw new BadRequestException(
          `Uploaded backup (${actualSize} bytes) exceeds the ${cap} byte limit for this backup`,
        );
      }
      await this.database.db
        .update(backups)
        .set({ uploadedAt: new Date() })
        .where(and(eq(backups.userId, userId), eq(backups.id, id)));
    }
    await this.prune(userId);
  }

  async list(userId: string, page = 1, limit = 50) {
    const offset = (page - 1) * limit;
    const [totalRow] = await this.database.db
      .select({ n: count() })
      .from(backups)
      .where(eq(backups.userId, userId));
    const rows = await this.database.db
      .select({
        backup: backups,
        deviceName: devices.name,
      })
      .from(backups)
      .leftJoin(devices, eq(devices.id, backups.deviceId))
      .where(eq(backups.userId, userId))
      .orderBy(desc(backups.createdAt))
      .limit(limit)
      .offset(offset);
    const total = totalRow?.n ?? 0;
    return {
      items: await Promise.all(
        rows.map(({ backup, deviceName }) => this.toView(backup, deviceName)),
      ),
      page,
      limit,
      total,
      hasMore: offset + rows.length < total,
    };
  }

  async downloadUrl(
    userId: string,
    id: string,
  ): Promise<{ downloadUrl: string; expiresInSeconds: number }> {
    const [row] = await this.requireRow(userId, id);
    if (!row.uploadedAt) {
      throw new NotFoundException('Backup has not finished uploading');
    }
    this.requireStorage();
    const downloadUrl = await this.minio.presignedGet(row.objectKey, GET_TTL_SECONDS);
    return { downloadUrl, expiresInSeconds: GET_TTL_SECONDS };
  }

  /** Restore is an async ack — the CLIENT downloads + decrypts + imports. */
  async restore(userId: string, id: string): Promise<{ status: 'accepted' }> {
    await this.requireRow(userId, id);
    return { status: 'accepted' };
  }

  /** Removes the oldest backups past the retention cap (object + row). */
  private async prune(userId: string): Promise<void> {
    const rows = await this.database.db
      .select()
      .from(backups)
      .where(and(eq(backups.userId, userId)))
      .orderBy(asc(backups.createdAt));
    const excess = rows.slice(0, Math.max(0, rows.length - this.retention));
    for (const row of excess) {
      await this.minio.remove(row.objectKey);
      await this.database.db
        .delete(backups)
        .where(and(eq(backups.userId, userId), eq(backups.id, row.id)));
    }
  }

  /** Stats the uploaded blob; maps a missing object to a clear 404. */
  private async verifyUploaded(objectKey: string): Promise<number> {
    this.requireStorage();
    try {
      return await this.minio.stat(objectKey);
    } catch (error) {
      if (this.minio.isMissingKeyError(error)) {
        throw new NotFoundException(
          'Upload not found — upload the object to MinIO before confirming',
        );
      }
      throw error;
    }
  }

  private requireStorage(): void {
    if (!this.minio.enabled) {
      throw new ServiceUnavailableException('Object storage is not configured');
    }
  }

  private async requireRow(
    userId: string,
    id: string,
  ): Promise<(typeof backups.$inferSelect)[]> {
    const rows = await this.database.db
      .select()
      .from(backups)
      .where(and(eq(backups.userId, userId), eq(backups.id, id)));
    if (rows.length === 0) throw new NotFoundException('Backup not found');
    return rows;
  }

  private async toView(
    row: typeof backups.$inferSelect,
    deviceNameOverride?: string | null,
  ): Promise<BackupView> {
    let deviceName = deviceNameOverride ?? null;
    if (deviceName === null && row.deviceId) {
      const [device] = await this.database.db
        .select({ name: devices.name })
        .from(devices)
        .where(eq(devices.id, row.deviceId));
      deviceName = device?.name ?? null;
    }
    return {
      id: row.id,
      deviceId: row.deviceId,
      deviceName,
      sizeBytes: row.sizeBytes,
      sha256: row.sha256,
      uploadedAt: row.uploadedAt,
      createdAt: row.createdAt,
    };
  }
}
