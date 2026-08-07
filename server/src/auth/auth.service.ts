import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { and, eq, isNull } from 'drizzle-orm';
import { createHash, randomBytes } from 'node:crypto';
import { DatabaseService } from '../database/database.service';
import { devices, passwordResetTokens, users } from '../drizzle/schema';
import { MailService } from '../mail/mail.service';
import { toPublicUser, UsersService } from '../users/users.service';
import { LoginAttemptsService } from './login-attempts.service';
import { LoginDto } from './dto/login.dto';
import { SignupDto } from './dto/signup.dto';
import { PasswordService } from './password.service';
import { RefreshTokenService, TokenPair } from './refresh-token.service';
import { TokenService } from './token.service';

const VERIFICATION_TOKEN_TTL_MS = 60 * 60_000; // 1 hour
const RESET_TOKEN_TTL_MS = 30 * 60_000; // 30 minutes

/**
 * Auth orchestration. The database is written only through Drizzle; every
 * failure is a typed Nest HttpException that the global filter turns into the
 * uniform error envelope (docs/BACKEND_API.md §1–2).
 */
@Injectable()
export class AuthService {
  constructor(
    private readonly database: DatabaseService,
    private readonly config: ConfigService,
    private readonly users: UsersService,
    private readonly password: PasswordService,
    private readonly tokens: TokenService,
    private readonly refreshTokens: RefreshTokenService,
    private readonly mail: MailService,
    private readonly attempts: LoginAttemptsService,
  ) {}

  // -------------------------------------------------------------------------
  // Signup / login
  // -------------------------------------------------------------------------

  async signup(dto: SignupDto) {
    const passwordHash = await this.password.hash(dto.password);
    const user = await this.users.create(dto.email, passwordHash);

    let verificationSent = false;
    if (this.mail.enabled) {
      const token = randomBytes(32).toString('hex');
      await this.users.setVerificationToken(user.id, this.hash(token));
      verificationSent = await this.mail.sendVerification(user.email, token);
    }

    return {
      user: toPublicUser(user),
      verification: {
        sent: verificationSent,
        expiresInSeconds: Math.floor(VERIFICATION_TOKEN_TTL_MS / 1000),
      },
    };
  }

  async login(dto: LoginDto, ip: string): Promise<TokenPair & { user: ReturnType<typeof toPublicUser> }> {
    const email = dto.email.toLowerCase().trim();
    await this.attempts.assertAllowed(email, ip);

    const user = await this.users.findByEmail(email);
    let passwordOk = false;
    if (user) {
      passwordOk = await this.password.verify(user.passwordHash, dto.password);
    } else {
      // Unknown email: burn the same Argon2 time so response timing cannot
      // reveal which emails have accounts (user enumeration).
      await this.password.burnTime(dto.password);
    }
    if (!user || !passwordOk) {
      await this.attempts.recordFailure(email, ip);
      throw new UnauthorizedException('Invalid email or password');
    }
    await this.attempts.recordSuccess(email);

    if (this.config.get<boolean>('EMAIL_VERIFICATION_REQUIRED') && !user.isVerified) {
      throw new ForbiddenException('Email not verified — check your inbox');
    }

    await this.upsertDevice(user.id, dto);
    // Re-login on the same install invalidates that install's old sessions.
    await this.refreshTokens.revokeByDevice(dto.deviceId, user.id);
    const pair = await this.refreshTokens.createPair(user.id, dto.deviceId);

    return { ...pair, user: toPublicUser(user) };
  }

  async refresh(refreshToken: string): Promise<TokenPair> {
    return this.refreshTokens.rotate(refreshToken);
  }

  async logout(
    userId: string,
    deviceId: string,
    dto: { refreshToken?: string },
  ): Promise<void> {
    if (dto.refreshToken) {
      await this.refreshTokens.revokeToken(dto.refreshToken);
    } else {
      await this.refreshTokens.revokeByDevice(deviceId, userId);
    }
  }

  async me(userId: string, deviceId: string) {
    const user = await this.users.findById(userId);
    if (!user) throw new UnauthorizedException('Account no longer exists');
    const device = await this.database.db.query.devices.findFirst({
      where: eq(devices.id, deviceId),
    });
    return {
      user: toPublicUser(user),
      device: device
        ? {
            id: device.id,
            name: device.name,
            platform: device.platform,
            appVersion: device.appVersion,
            current: device.id === deviceId,
          }
        : null,
    };
  }

  // -------------------------------------------------------------------------
  // Email verification
  // -------------------------------------------------------------------------

  async verifyEmail(token: string): Promise<void> {
    const user = await this.database.db.query.users.findFirst({
      where: eq(users.verificationTokenHash, this.hash(token)),
    });
    if (!user) throw new BadRequestException('Invalid or expired verification token');
    // The email promises 60 minutes; enforce it (tokens are created only at
    // signup, so createdAt is the issuance time).
    if (Date.now() > user.createdAt.getTime() + VERIFICATION_TOKEN_TTL_MS) {
      throw new BadRequestException('Invalid or expired verification token');
    }
    await this.users.setVerified(user.id);
  }

  // -------------------------------------------------------------------------
  // Password reset
  // -------------------------------------------------------------------------

  async requestPasswordReset(email: string): Promise<{ sent: boolean }> {
    const user = await this.users.findByEmail(email);
    // Always 202 with the same shape — `sent` reflects only whether mail is
    // configured, never whether the account exists (no enumeration).
    if (!user || !this.mail.enabled) return { sent: this.mail.enabled };

    const token = randomBytes(32).toString('hex');
    await this.database.db.transaction(async (tx) => {
      // Invalidate every outstanding token for this user — a previously
      // issued (still-unexpired) reset token must not survive a newer
      // request, otherwise an attacker with a leaked old token could reset
      // the password even after the owner asked for a fresh one.
      await tx
        .update(passwordResetTokens)
        .set({ usedAt: new Date() })
        .where(
          and(
            eq(passwordResetTokens.userId, user.id),
            isNull(passwordResetTokens.usedAt),
          ),
        );
      await tx.insert(passwordResetTokens).values({
        userId: user.id,
        tokenHash: this.hash(token),
        expiresAt: new Date(Date.now() + RESET_TOKEN_TTL_MS),
      });
    });
    await this.mail.sendPasswordReset(user.email, token);
    return { sent: true };
  }

  async confirmPasswordReset(token: string, newPassword: string): Promise<void> {
    const row = await this.database.db.query.passwordResetTokens.findFirst({
      where: eq(passwordResetTokens.tokenHash, this.hash(token)),
    });
    if (
      !row ||
      row.usedAt !== null ||
      row.expiresAt.getTime() <= Date.now()
    ) {
      throw new BadRequestException('Invalid or expired reset token');
    }

    const passwordHash = await this.password.hash(newPassword);
    await this.database.db.transaction(async (tx) => {
      await tx
        .update(passwordResetTokens)
        .set({ usedAt: new Date() })
        .where(eq(passwordResetTokens.id, row.id));
      await tx.update(users).set({ passwordHash }).where(eq(users.id, row.userId));
    });
    // All sessions die — the password change is authoritative.
    await this.refreshTokens.revokeByUser(row.userId);
  }

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  /** Registers or re-activates the client's install (devices.id = deviceId). */
  private async upsertDevice(
    userId: string,
    dto: LoginDto,
  ): Promise<void> {
    await this.database.db
      .insert(devices)
      .values({
        id: dto.deviceId,
        userId,
        name: dto.deviceName ?? null,
        platform: dto.platform,
        appVersion: dto.appVersion ?? null,
        lastSeenAt: new Date(),
      })
      .onConflictDoUpdate({
        target: devices.id,
        set: {
          name: dto.deviceName ?? null,
          platform: dto.platform,
          appVersion: dto.appVersion ?? null,
          revokedAt: null, // re-activate a previously revoked install
          lastSeenAt: new Date(),
        },
      });
  }

  private hash(value: string): string {
    return createHash('sha256').update(value).digest('hex');
  }
}
