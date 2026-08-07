import { Type } from 'class-transformer';
import {
  ArrayMaxSize,
  IsArray,
  IsDateString,
  IsIn,
  IsInt,
  IsObject,
  IsOptional,
  IsString,
  IsUUID,
  MaxLength,
  Min,
  ValidateNested,
} from 'class-validator';

/** Entities that flow through the operation log (docs/BACKEND_API.md §4). */
export const SYNC_ENTITIES = [
  'account',
  'tag',
  'transaction',
  'bill',
  'budget',
  'app_setting',
] as const;

export const SYNC_OPERATIONS = ['upsert', 'delete'] as const;

/** Max ops per push batch (contract: ≤ 500). */
export const MAX_PUSH_BATCH = 500;

/** Max rows returned per pull page. */
export const MAX_PULL_PAGE = 1000;

export class SyncOpDto {
  @IsUUID()
  opId!: string;

  @IsIn(SYNC_ENTITIES)
  entity!: string;

  /** Client row id (text, opaque) — the current-state primary key. */
  @IsString()
  @MaxLength(255)
  entityId!: string;

  /** Must match the JWT `device` claim (verified in SyncService). */
  @IsUUID()
  deviceId!: string;

  @IsIn(SYNC_OPERATIONS)
  operation!: string;

  /** The version this edit was based on (CAS guard). */
  @IsInt()
  @Min(0)
  baseVersion!: number;

  /** The version this edit produces (must exceed baseVersion). */
  @IsInt()
  @Min(1)
  version!: number;

  /** Full entity row, snake_case (null for deletes). */
  @IsOptional()
  @IsObject()
  payload?: Record<string, unknown> | null;

  @IsDateString()
  updatedAt!: string;

  @IsOptional()
  @IsDateString()
  deletedAt?: string | null;
}

export class PushDto {
  @IsArray()
  @ArrayMaxSize(MAX_PUSH_BATCH, {
    message: `a push batch may contain at most ${MAX_PUSH_BATCH} operations`,
  })
  @ValidateNested({ each: true })
  @Type(() => SyncOpDto)
  ops!: SyncOpDto[];
}
