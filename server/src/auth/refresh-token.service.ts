import { Injectable, UnauthorizedException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { and, eq, isNull } from 'drizzle-orm';
import { randomUUID } from 'node:crypto';
import { DatabaseService } from '../database/database.service';
import { devices, refreshTokens } from '../drizzle/schema';
import { TokenService } from './token.service';

export interface TokenPair {
  accessToken: string;
  refreshToken: string;
  /** Seconds the access token remains valid (for the client's timer). */
  expiresIn: number;
}

/**
 * Refresh-token lifecycle. Tokens are opaque, bound to (user, device),
 * hashed at rest, rotated on every use and revoked on logout / device
 * revocation / password change. Presenting an already-used token triggers
 * whole-device chain revocation (reuse = stolen-token signal).
 */
@Injectable()
export class RefreshTokenService {
  private readonly ttlDays: number;
  private readonly accessTtlSeconds: number;

  constructor(
    private readonly database: DatabaseService,
    private readonly config: ConfigService,
    private readonly tokens: TokenService,
  ) {
    this.ttlDays = this.config.get<number>('REFRESH_TTL_DAYS', 30);
    this.accessTtlSeconds = this.config.get<number>('JWT_ACCESS_TTL_SECONDS', 900);
  }

  async createPair(userId: string, deviceId: string): Promise<TokenPair> {
    const refreshToken = this.tokens.generateRefreshToken();
    const id = randomUUID();
    await this.database.db.insert(refreshTokens).values({
      id,
      userId,
      deviceId,
      tokenHash: this.tokens.hashRefreshToken(refreshToken),
      expiresAt: this.expiry(),
    });
    return {
      accessToken: await this.tokens.signAccessToken(userId, deviceId, id),
      refreshToken,
      expiresIn: this.accessTtlSeconds,
    };
  }

  /** Rotates a presented refresh token, revoking it and issuing a new pair. */
  async rotate(presentedToken: string): Promise<TokenPair> {
    const row = await this.database.db.query.refreshTokens.findFirst({
      where: eq(refreshTokens.tokenHash, this.tokens.hashRefreshToken(presentedToken)),
    });
    if (!row) {
      throw new UnauthorizedException('Invalid refresh token');
    }
    if (row.revokedAt) {
      // Token reuse — treat as theft: kill every session on the device.
      if (row.deviceId) await this.revokeByDevice(row.deviceId, row.userId);
      throw new UnauthorizedException('Refresh token already used');
    }
    if (row.expiresAt.getTime() <= Date.now()) {
      await this.revokeOne(row.id);
      throw new UnauthorizedException('Refresh token expired');
    }
    if (!row.deviceId) {
      // Every token issued in Phase 2 is device-bound; a row without one is
      // either corrupt or legacy — refuse it and retire it.
      await this.revokeOne(row.id);
      throw new UnauthorizedException('Invalid refresh token');
    }
    {
      const device = await this.database.db.query.devices.findFirst({
        where: eq(devices.id, row.deviceId),
      });
      if (!device || device.revokedAt) {
        throw new UnauthorizedException('Device revoked');
      }
    }

    const refreshToken = this.tokens.generateRefreshToken();
    const newId = randomUUID();
    await this.database.db.transaction(async (tx) => {
      // Guarded UPDATE: `revoked_at IS NULL` makes the rotation atomic. If two
      // requests race on the same token, exactly one wins the UPDATE; the loser
      // matches 0 rows and is treated as reuse (chain revocation below).
      const claimed = await tx
        .update(refreshTokens)
        .set({ revokedAt: new Date(), replacedBy: newId })
        .where(
          and(eq(refreshTokens.id, row.id), isNull(refreshTokens.revokedAt)),
        )
        .returning({ id: refreshTokens.id });
      if (claimed.length === 0) {
        if (row.deviceId) {
          await this.revokeByDevice(row.deviceId, row.userId);
        }
        throw new UnauthorizedException('Refresh token already used');
      }
      await tx.insert(refreshTokens).values({
        id: newId,
        userId: row.userId,
        deviceId: row.deviceId,
        tokenHash: this.tokens.hashRefreshToken(refreshToken),
        expiresAt: this.expiry(),
      });
    });

    return {
      accessToken: await this.tokens.signAccessToken(row.userId, row.deviceId, newId),
      refreshToken,
      expiresIn: this.accessTtlSeconds,
    };
  }

  async revokeToken(presentedToken: string): Promise<void> {
    const row = await this.database.db.query.refreshTokens.findFirst({
      where: eq(refreshTokens.tokenHash, this.tokens.hashRefreshToken(presentedToken)),
    });
    if (row && !row.revokedAt) await this.revokeOne(row.id);
  }

  async revokeByDevice(deviceId: string, userId?: string): Promise<void> {
    await this.database.db
      .update(refreshTokens)
      .set({ revokedAt: new Date() })
      .where(
        and(
          eq(refreshTokens.deviceId, deviceId),
          isNull(refreshTokens.revokedAt),
          userId ? eq(refreshTokens.userId, userId) : undefined,
        ),
      );
  }

  async revokeByUser(userId: string): Promise<void> {
    await this.database.db
      .update(refreshTokens)
      .set({ revokedAt: new Date() })
      .where(and(eq(refreshTokens.userId, userId), isNull(refreshTokens.revokedAt)));
  }

  private async revokeOne(id: string): Promise<void> {
    await this.database.db
      .update(refreshTokens)
      .set({ revokedAt: new Date() })
      .where(eq(refreshTokens.id, id));
  }

  private expiry(): Date {
    return new Date(Date.now() + this.ttlDays * 86_400_000);
  }
}
