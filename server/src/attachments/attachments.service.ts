import {
  BadRequestException,
  Injectable,
  NotFoundException,
  ServiceUnavailableException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { and, eq } from 'drizzle-orm';
import { randomUUID } from 'node:crypto';
import { DatabaseService } from '../database/database.service';
import { attachments, transactions } from '../drizzle/schema';
import { MinioService } from '../storage/minio.service';
import { CreateAttachmentDto } from './attachment.dto';

const PUT_TTL_SECONDS = 900;
const GET_TTL_SECONDS = 3600;

export interface AttachmentView {
  id: string;
  transactionId: string | null;
  mimeType: string;
  sizeBytes: number;
  sha256: string;
  uploadedAt: Date | null;
  createdAt: Date;
}

@Injectable()
export class AttachmentsService {
  private readonly maxBytes: number;

  constructor(
    private readonly database: DatabaseService,
    private readonly minio: MinioService,
    config: ConfigService,
  ) {
    this.maxBytes = config.get<number>('MAX_ATTACHMENT_BYTES', 25 * 1024 * 1024);
  }

  /**
   * Creates the metadata row and returns a one-shot presigned PUT URL. The
   * client uploads the blob directly to MinIO, then PATCHes `{ uploaded: true }`.
   */
  async create(
    userId: string,
    dto: CreateAttachmentDto,
  ): Promise<{ attachment: AttachmentView; uploadUrl: string; expiresInSeconds: number }> {
    if (!this.minio.enabled) {
      throw new ServiceUnavailableException('Object storage is not configured');
    }
    // The contract promises a server-side size policy — enforce it here so a
    // client cannot request a presigned URL for an unbounded object.
    if (dto.sizeBytes > this.maxBytes) {
      throw new BadRequestException(
        `Attachment exceeds the ${this.maxBytes} byte limit`,
      );
    }

    // Validate the transaction (if given) belongs to this user.
    if (dto.transactionId) {
      const [txn] = await this.database.db
        .select({ id: transactions.id })
        .from(transactions)
        .where(
          and(eq(transactions.userId, userId), eq(transactions.id, dto.transactionId)),
        );
      if (!txn) throw new NotFoundException('Transaction not found');
    }

    const id = randomUUID();
    const objectKey = `attachments/${userId}/${id}`;
    await this.database.db.insert(attachments).values({
      id,
      userId,
      transactionId: dto.transactionId ?? null,
      objectKey,
      mimeType: dto.mimeType,
      sizeBytes: dto.sizeBytes,
      sha256: dto.sha256,
    });

    const uploadUrl = await this.minio.presignedPut(objectKey, PUT_TTL_SECONDS);
    const [row] = await this.requireRow(userId, id);
    return {
      attachment: this.toView(row),
      uploadUrl,
      expiresInSeconds: PUT_TTL_SECONDS,
    };
  }

  /**
   * Marks the upload confirmed. The presigned PUT URL cannot constrain the
   * upload size, so the declared `sizeBytes` is only a claim until we stat
   * the object: confirm verifies the blob exists and fits the policy, and
   * removes over-limit objects rather than letting them linger.
   */
  async confirm(userId: string, id: string): Promise<void> {
    const [row] = await this.requireRow(userId, id);
    if (!row.uploadedAt) {
      const actualSize = await this.verifyUploaded(row.objectKey);
      // Reject when the blob exceeds EITHER the declared size (the client
      // lied or bugged) OR the policy cap — declaring a tiny size must not
      // bypass the limit.
      const cap = Math.min(row.sizeBytes, this.maxBytes);
      if (actualSize > cap) {
        await this.minio.remove(row.objectKey);
        throw new BadRequestException(
          `Uploaded object (${actualSize} bytes) exceeds the ${cap} byte limit for this attachment`,
        );
      }
      await this.database.db
        .update(attachments)
        .set({ uploadedAt: new Date() })
        .where(and(eq(attachments.userId, userId), eq(attachments.id, id)));
    }
  }

  async downloadUrl(
    userId: string,
    id: string,
  ): Promise<{ downloadUrl: string; expiresInSeconds: number }> {
    const [row] = await this.requireRow(userId, id);
    if (!row.uploadedAt) {
      throw new NotFoundException('Attachment has not finished uploading');
    }
    this.requireStorage();
    const downloadUrl = await this.minio.presignedGet(row.objectKey, GET_TTL_SECONDS);
    return { downloadUrl, expiresInSeconds: GET_TTL_SECONDS };
  }

  async remove(userId: string, id: string): Promise<void> {
    const [row] = await this.requireRow(userId, id);
    // Remove the object first; if that fails we still delete the row (the
    // orphaned object is a cleanup job's concern).
    if (this.minio.enabled) {
      await this.minio.remove(row.objectKey);
    }
    await this.database.db
      .delete(attachments)
      .where(and(eq(attachments.userId, userId), eq(attachments.id, id)));
  }

  /** Stats the uploaded object; maps a missing object to a clear 404. */
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
  ): Promise<(typeof attachments.$inferSelect)[]> {
    const rows = await this.database.db
      .select()
      .from(attachments)
      .where(and(eq(attachments.userId, userId), eq(attachments.id, id)));
    if (rows.length === 0) throw new NotFoundException('Attachment not found');
    return rows;
  }

  private toView(row: typeof attachments.$inferSelect): AttachmentView {
    return {
      id: row.id,
      transactionId: row.transactionId,
      mimeType: row.mimeType,
      sizeBytes: row.sizeBytes,
      sha256: row.sha256,
      uploadedAt: row.uploadedAt,
      createdAt: row.createdAt,
    };
  }
}
