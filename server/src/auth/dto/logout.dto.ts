import { IsOptional, IsString } from 'class-validator';

export class LogoutDto {
  /** When present, only this token is revoked; otherwise all device tokens. */
  @IsOptional()
  @IsString()
  refreshToken?: string;
}
