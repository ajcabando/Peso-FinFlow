import { IsInt, IsOptional, IsString, Matches, Max, Min } from 'class-validator';

export class CreateBackupDto {
  @IsString()
  @Matches(/^[0-9a-f]{64}$/, { message: 'sha256 must be 64 lowercase hex characters' })
  sha256!: string;

  @IsInt()
  @Min(1)
  sizeBytes!: number;

  @IsOptional()
  @IsString()
  deviceName?: string | null;
}

export class ListBackupsQueryDto {
  @IsOptional()
  @IsInt()
  @Min(1)
  page?: number;

  @IsOptional()
  @IsInt()
  @Min(1)
  @Max(100)
  limit?: number;
}
