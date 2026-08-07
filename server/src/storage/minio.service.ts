import { Injectable, Logger, OnModuleInit } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import * as Minio from 'minio';

/**
 * Thin wrapper over the MinIO SDK. The bucket is private; every upload and
 * download happens through short-lived presigned URLs issued by the API after
 * ownership checks — blobs never transit through the API body.
 *
 * When `MINIO_ENDPOINT` is empty (env default) storage is disabled: all
 * methods throw a clear 503-equivalent error and /health/ready reports
 * `minio: down` — attachments/backup endpoints are unusable, sync still works.
 */
@Injectable()
export class MinioService implements OnModuleInit {
  private readonly logger = new Logger(MinioService.name);
  private readonly client: Minio.Client | null;

  constructor(config: ConfigService) {
    const endpoint = config.get<string>('MINIO_ENDPOINT', '');
    if (!endpoint) {
      this.logger.warn(
        'MINIO_ENDPOINT is empty — object storage disabled (attachments/backups unavailable)',
      );
      this.client = null;
      return;
    }
    this.client = new Minio.Client({
      endPoint: endpoint,
      port: config.get<number>('MINIO_PORT', 9000),
      useSSL: config.get<boolean>('MINIO_USE_SSL', false),
      accessKey: config.get<string>('MINIO_ACCESS_KEY', ''),
      secretKey: config.get<string>('MINIO_SECRET_KEY', ''),
    });
    this.bucket = config.get<string>('MINIO_BUCKET', 'finflow');
  }

  readonly bucket: string = 'finflow';

  get enabled(): boolean {
    return this.client !== null;
  }

  /** Creates the bucket if missing (idempotent). Runs at app boot. */
  async onModuleInit(): Promise<void> {
    if (!this.client) return;
    try {
      const exists = await this.client.bucketExists(this.bucket);
      if (!exists) {
        await this.client.makeBucket(this.bucket);
        this.logger.log(`Created MinIO bucket "${this.bucket}"`);
      }
    } catch (error) {
      // Do not crash the app — health checks surface the problem. The API is
      // lazy: storage endpoints fail per-request until MinIO is reachable.
      this.logger.error(`MinIO bucket bootstrap failed: ${String(error)}`);
    }
  }

  /** One-shot presigned PUT for a client upload. */
  async presignedPut(objectKey: string, expiresSeconds = 900): Promise<string> {
    return this.requireClient().presignedPutObject(
      this.bucket,
      objectKey,
      expiresSeconds,
    );
  }

  /** Presigned GET for a client download. */
  async presignedGet(
    objectKey: string,
    expiresSeconds = 3600,
  ): Promise<string> {
    return this.requireClient().presignedGetObject(
      this.bucket,
      objectKey,
      expiresSeconds,
    );
  }

  /** Returns the stored object's size in bytes; throws when the key is missing. */
  async stat(objectKey: string): Promise<number> {
    const info = await this.requireClient().statObject(this.bucket, objectKey);
    return info.size;
  }

  /** Removes the object. Never throws for a missing key. */
  async remove(objectKey: string): Promise<void> {
    const client = this.requireClient();
    try {
      await client.removeObject(this.bucket, objectKey);
    } catch (error) {
      this.logger.warn(`MinIO removeObject failed for ${objectKey}: ${String(error)}`);
    }
  }

  /**
   * Health probe: stat against the bucket. A missing object (404) still proves
   * bucket + credentials work — anything else (AccessDenied, timeout, …) is a
   * real failure and must NOT be swallowed or /health/ready would report
   * `minio: up` with broken credentials.
   */
  async ping(): Promise<void> {
    let timeout: ReturnType<typeof setTimeout> | undefined;
    try {
      // Hard timeout — a black-holed network must degrade /health/ready, not
      // hang it (mirrors the Redis probe bound).
      await Promise.race([
        this.requireClient().statObject(this.bucket, '__health_probe__'),
        new Promise((_, reject) => {
          timeout = setTimeout(
            () => reject(new Error('MinIO probe timed out')),
            2000,
          );
        }),
      ]);
    } catch (error) {
      if (!this.isMissingKeyError(error)) throw error;
    } finally {
      clearTimeout(timeout);
    }
  }

  /**
   * True when the S3 error means "the object does not exist" (bucket + creds
   * are fine). minio-js reports a missing stat as `NotFound`, older SDKs as
   * `NoSuchKey` — both mean the key is absent.
   */
  isMissingKeyError(error: unknown): boolean {
    const code = (error as { code?: string }).code;
    return code === 'NoSuchKey' || code === 'NotFound';
  }

  private requireClient(): Minio.Client {
    if (!this.client) {
      throw new Error('Object storage is not configured (MINIO_ENDPOINT is empty)');
    }
    return this.client;
  }
}
