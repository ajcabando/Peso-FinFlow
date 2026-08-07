import { z } from 'zod';

/**
 * Environment schema — validated once at boot by `ConfigModule.forRoot`.
 * Phase-2 scope adds auth: JWT signing, Argon2id params, email verification,
 * SMTP (Nodemailer) and auth-specific rate limits. MinIO / Redis / backup
 * variables are documented in `.env.example` and are added as their phases
 * land.
 */
const logLevels = ['fatal', 'error', 'warn', 'info', 'debug', 'trace', 'silent'] as const;
const booleanFromString = z
  .enum(['true', 'false'])
  .default('false')
  .transform((value) => value === 'true');

export const envSchema = z.object({
  NODE_ENV: z
    .enum(['development', 'test', 'production'])
    .default('development'),

  // HTTP
  PORT: z.coerce.number().int().positive().default(8080),
  API_PREFIX: z.string().min(1).default('/v1'),
  CORS_ORIGINS: z
    .string()
    .default('') // comma-separated allow-list; empty = no cross-origin access
    .transform((v) =>
      v
        .split(',')
        .map((s) => s.trim())
        .filter(Boolean),
    ),

  // Database
  DATABASE_URL: z
    .string()
    .min(1, 'DATABASE_URL is required (postgres://user:pass@host:5432/db)'),

  // Rate limiting (global, per-IP)
  THROTTLE_TTL_SECONDS: z.coerce.number().int().positive().default(60),
  THROTTLE_LIMIT: z.coerce.number().int().positive().default(300),

  // Logging
  LOG_LEVEL: z.enum(logLevels).default('info'),

  // -------------------------------------------------------------------------
  // Auth (Phase 2)
  // -------------------------------------------------------------------------
  JWT_ACCESS_SECRET: z
    .string()
    .min(32, 'JWT_ACCESS_SECRET required (≥32 chars) — generate with: openssl rand -base64 48'),
  JWT_ACCESS_TTL_SECONDS: z.coerce.number().int().positive().default(900),
  REFRESH_TTL_DAYS: z.coerce.number().int().positive().default(30),

  // Argon2id (OWASP-recommended parameters)
  ARGON2_MEMORY_KIB: z.coerce.number().int().positive().default(19456),
  ARGON2_ITERATIONS: z.coerce.number().int().positive().default(2),
  ARGON2_PARALLELISM: z.coerce.number().int().positive().default(1),

  EMAIL_VERIFICATION_REQUIRED: booleanFromString,
  APP_URL: z.string().url().default('http://localhost:8080'),

  // SMTP (Nodemailer) — empty SMTP_HOST disables all mail.
  SMTP_HOST: z.string().default(''),
  SMTP_PORT: z.coerce.number().int().positive().default(587),
  SMTP_USER: z.string().default(''),
  SMTP_PASS: z.string().default(''),
  SMTP_FROM: z.string().min(1).default('FinFlow <no-reply@finflow.local>'),

  // Auth rate limiting (LoginAttemptsService; Redis-backed when REDIS_URL is
  // set, in-memory fallback otherwise — shared across instances when scaled).
  AUTH_MAX_ATTEMPTS_PER_MINUTE: z.coerce.number().int().positive().default(5),
  AUTH_MAX_FAILURES_PER_HOUR: z.coerce.number().int().positive().default(10),

  // -------------------------------------------------------------------------
  // Object storage — MinIO (Phase 4). Empty MINIO_ENDPOINT disables storage.
  // -------------------------------------------------------------------------
  MINIO_ENDPOINT: z.string().default(''),
  MINIO_PORT: z.coerce.number().int().positive().default(9000),
  MINIO_ACCESS_KEY: z.string().default(''),
  MINIO_SECRET_KEY: z.string().default(''),
  MINIO_BUCKET: z.string().default('finflow'),
  MINIO_USE_SSL: booleanFromString,
  // Max attachment size in bytes (presigned PUT policy).
  MAX_ATTACHMENT_BYTES: z.coerce.number().int().positive().default(25 * 1024 * 1024),

  // -------------------------------------------------------------------------
  // Backups (Phase 4)
  // -------------------------------------------------------------------------
  BACKUP_RETENTION: z.coerce.number().int().positive().default(10),
  // Max backup blob size in bytes (declared at create, verified at confirm).
  MAX_BACKUP_BYTES: z.coerce.number().int().positive().default(100 * 1024 * 1024),

  // -------------------------------------------------------------------------
  // Redis (Phase 4+) — empty REDIS_URL disables Redis (limiter falls back to
  // in-memory; health check skips it).
  // -------------------------------------------------------------------------
  REDIS_URL: z.string().default(''),
});

export type Env = z.infer<typeof envSchema>;

/**
 * ConfigModule `validate` hook. Throws a single, readable error listing every
 * problem so a misconfigured deploy dies at boot instead of at request time.
 */
export function validateEnv(config: Record<string, unknown>): Env {
  const parsed = envSchema.safeParse(config);
  if (!parsed.success) {
    const issues = parsed.error.issues
      .map((issue) => `  - ${issue.path.join('.')}: ${issue.message}`)
      .join('\n');
    throw new Error(`Invalid environment configuration:\n${issues}`);
  }

  const env = parsed.data;
  // Fail-fast cross-field invariants.
  if (env.EMAIL_VERIFICATION_REQUIRED && !env.SMTP_HOST) {
    throw new Error(
      'Invalid environment configuration:\n' +
        '  - EMAIL_VERIFICATION_REQUIRED=true requires SMTP_HOST (verification emails cannot be sent otherwise)',
    );
  }
  return env;
}
