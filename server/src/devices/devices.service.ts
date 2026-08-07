import { Injectable, NotFoundException } from '@nestjs/common';
import { and, desc, eq } from 'drizzle-orm';
import { DatabaseService } from '../database/database.service';
import { devices } from '../drizzle/schema';
import { RefreshTokenService } from '../auth/refresh-token.service';

export interface DeviceView {
  id: string;
  name: string | null;
  platform: string | null;
  appVersion: string | null;
  lastSyncAt: Date | null;
  revokedAt: Date | null;
  current: boolean;
}

@Injectable()
export class DevicesService {
  constructor(
    private readonly database: DatabaseService,
    private readonly refreshTokens: RefreshTokenService,
  ) {}

  async listForUser(userId: string, currentDeviceId: string): Promise<DeviceView[]> {
    const rows = await this.database.db
      .select()
      .from(devices)
      .where(eq(devices.userId, userId))
      .orderBy(desc(devices.createdAt));
    return rows.map((row) => ({
      id: row.id,
      name: row.name,
      platform: row.platform,
      appVersion: row.appVersion,
      lastSyncAt: row.lastSyncAt,
      revokedAt: row.revokedAt,
      current: row.id === currentDeviceId,
    }));
  }

  /**
   * Revokes a device — scoped to the caller's own rows. Another user's device
   * id returns 404 (never confirms it exists).
   *
   * NOTE: this UPDATE takes a row lock on the device, which serialises with
   * SyncService.push's in-transaction `SELECT … FOR UPDATE` re-check. An
   * in-flight push (which holds the lock for the whole batch) completes before
   * the revoke lands — an accepted window, do NOT "fix" the apparent
   * contention by removing that FOR UPDATE.
   */
  async revoke(userId: string, deviceId: string): Promise<void> {
    const claimed = await this.database.db
      .update(devices)
      .set({ revokedAt: new Date() })
      .where(and(eq(devices.id, deviceId), eq(devices.userId, userId)))
      .returning({ id: devices.id });
    if (claimed.length === 0) {
      throw new NotFoundException('Device not found');
    }
    // Kill every session on the device (scoped to the owner).
    await this.refreshTokens.revokeByDevice(deviceId, userId);
  }
}
