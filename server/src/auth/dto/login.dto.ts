import {
  IsEmail,
  IsIn,
  IsOptional,
  IsString,
  IsUUID,
  MaxLength,
  MinLength,
} from 'class-validator';

export const SUPPORTED_PLATFORMS = ['android', 'ios', 'ipados', 'web', 'macos'] as const;

export class LoginDto {
  @IsEmail()
  email!: string;

  @IsString()
  @MinLength(8, { message: 'password must be at least 8 characters' })
  @MaxLength(128)
  password!: string;

  /** Client-generated, persisted per install — becomes devices.id. */
  @IsUUID()
  deviceId!: string;

  @IsOptional()
  @IsString()
  @MaxLength(100)
  deviceName?: string;

  @IsIn(SUPPORTED_PLATFORMS)
  platform!: string;

  @IsOptional()
  @IsString()
  @MaxLength(30)
  appVersion?: string;
}
