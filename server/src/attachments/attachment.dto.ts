import {
  IsInt,
  IsOptional,
  IsString,
  IsUUID,
  Matches,
  Max,
  MaxLength,
  Min,
  MinLength,
} from 'class-validator';

export class CreateAttachmentDto {
  @IsOptional()
  @IsUUID()
  transactionId?: string | null;

  @IsString()
  @MinLength(1)
  @MaxLength(200)
  mimeType!: string;

  @IsInt()
  @Min(1)
  sizeBytes!: number;

  /** 64 lowercase hex chars (sha256 of the plaintext blob). */
  @IsString()
  @Matches(/^[0-9a-f]{64}$/, { message: 'sha256 must be 64 lowercase hex characters' })
  sha256!: string;
}

export class ConfirmUploadDto {
  @IsOptional()
  uploaded?: boolean;
}
