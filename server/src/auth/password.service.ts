import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import * as argon2 from 'argon2';

/**
 * Argon2id password hashing (OWASP parameters: m=19456 KiB, t=2, p=1 —
 * configurable via env). Passwords are never logged, stored or returned;
 * only the Argon2id hash lives in the database.
 */
@Injectable()
export class PasswordService {
  /**
   * A valid Argon2id hash of a throwaway value, verified against whenever the
   * login email has no account — equalising timing so "no such user" and
   * "wrong password" take the same amount of work (no user enumeration via
   * response time).
   */
  private static readonly DUMMY_HASH =
    '$argon2id$v=19$m=19456,t=2,p=1$vPqcZKOg9oHY50aA6nnpHw$BOkv2sM7X2i+cqHY2XsHKvNZrXoq28E8typy+E2YAGU';

  constructor(private readonly config: ConfigService) {}

  private get options(): argon2.Options {
    return {
      type: argon2.argon2id,
      memoryCost: this.config.get<number>('ARGON2_MEMORY_KIB', 19456),
      timeCost: this.config.get<number>('ARGON2_ITERATIONS', 2),
      parallelism: this.config.get<number>('ARGON2_PARALLELISM', 1),
    };
  }

  async hash(plain: string): Promise<string> {
    return argon2.hash(plain, this.options);
  }

  /** Never throws — a malformed stored hash just means "no match". */
  async verify(storedHash: string, plain: string): Promise<boolean> {
    try {
      return await argon2.verify(storedHash, plain);
    } catch {
      return false;
    }
  }

  /** Runs a full Argon2 verify against a known-wrong hash — timing equaliser. */
  async burnTime(plain: string): Promise<void> {
    await this.verify(PasswordService.DUMMY_HASH, plain);
  }
}
