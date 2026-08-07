import { Injectable, UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { createHash, randomBytes } from 'node:crypto';
import { CurrentUser } from './current-user.interface';

interface AccessTokenPayload {
  sub: string; // users.id
  device: string; // devices.id
  jti: string; // refresh-token row id
}

/**
 * Access + refresh tokens.
 *
 * Access tokens are short-lived JWTs (HS256) carrying `sub` (user),
 * `device` (device id) and `jti` (the refresh-token row id).
 * Refresh tokens are opaque 384-bit values stored **hashed** (SHA-256) — the
 * database never holds a usable token, so a dump cannot be replayed.
 */
@Injectable()
export class TokenService {
  constructor(private readonly jwt: JwtService) {}

  signAccessToken(userId: string, deviceId: string, jti: string): Promise<string> {
    return this.jwt.signAsync({ device: deviceId } satisfies Partial<AccessTokenPayload>, {
      subject: userId,
      jwtid: jti,
      issuer: 'finflow',
      audience: 'finflow-api',
    });
  }

  verifyAccessToken(token: string): CurrentUser {
    let payload: AccessTokenPayload;
    try {
      payload = this.jwt.verify<AccessTokenPayload>(token, {
        issuer: 'finflow',
        audience: 'finflow-api',
      });
    } catch {
      throw new UnauthorizedException('Invalid or expired access token');
    }
    if (!payload.sub || !payload.device || !payload.jti) {
      throw new UnauthorizedException('Invalid token claims');
    }
    return { userId: payload.sub, deviceId: payload.device, jti: payload.jti };
  }

  /** Opaque, unguessable refresh token. */
  generateRefreshToken(): string {
    return randomBytes(48).toString('base64url');
  }

  /** Deterministic hash of a refresh token — what the DB stores. */
  hashRefreshToken(token: string): string {
    return createHash('sha256').update(token).digest('hex');
  }
}
