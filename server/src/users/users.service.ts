import { ConflictException, Injectable } from '@nestjs/common';
import { eq } from 'drizzle-orm';
import { DatabaseService } from '../database/database.service';
import { users } from '../drizzle/schema';

export interface PublicUser {
  id: string;
  email: string;
  isVerified: boolean;
}

/** The only shape of a user that ever leaves the service layer. */
export function toPublicUser(row: {
  id: string;
  email: string;
  isVerified: boolean;
}): PublicUser {
  return { id: row.id, email: row.email, isVerified: row.isVerified };
}

@Injectable()
export class UsersService {
  constructor(private readonly database: DatabaseService) {}

  async findByEmail(rawEmail: string) {
    const email = rawEmail.toLowerCase().trim();
    return this.database.db.query.users.findFirst({
      where: eq(users.email, email),
    });
  }

  async findById(id: string) {
    return this.database.db.query.users.findFirst({
      where: eq(users.id, id),
    });
  }

  async create(rawEmail: string, passwordHash: string) {
    const email = rawEmail.toLowerCase().trim();
    try {
      const [row] = await this.database.db
        .insert(users)
        .values({ email, passwordHash })
        .returning();
      return row;
    } catch (error) {
      if (isUniqueViolation(error)) {
        throw new ConflictException('An account with this email already exists');
      }
      throw error;
    }
  }

  async setVerificationToken(userId: string, tokenHash: string) {
    await this.database.db
      .update(users)
      .set({ verificationTokenHash: tokenHash })
      .where(eq(users.id, userId));
  }

  async setVerified(userId: string) {
    await this.database.db
      .update(users)
      .set({ isVerified: true, verificationTokenHash: null })
      .where(eq(users.id, userId));
  }

  async setPassword(userId: string, passwordHash: string) {
    await this.database.db
      .update(users)
      .set({ passwordHash })
      .where(eq(users.id, userId));
  }
}

/** Postgres error 23505 = unique_violation. Drizzle wraps the pg error in
 * `cause`, so walk the cause chain (up to 3 levels) looking for the code. */
function isUniqueViolation(error: unknown): boolean {
  let current: unknown = error;
  for (let depth = 0; depth < 3; depth++) {
    if (typeof current !== 'object' || current === null) return false;
    const candidate = current as { code?: unknown; cause?: unknown };
    if (candidate.code === '23505') return true;
    current = candidate.cause;
  }
  return false;
}
