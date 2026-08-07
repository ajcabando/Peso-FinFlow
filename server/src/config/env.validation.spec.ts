import { validateEnv } from './env.validation';

describe('validateEnv', () => {
  const base = {
    DATABASE_URL: 'postgres://finflow:secret@postgres:5432/finflow',
    JWT_ACCESS_SECRET: 'x'.repeat(40),
  };

  it('accepts a minimal valid environment with defaults', () => {
    const env = validateEnv(base);
    expect(env.DATABASE_URL).toBe(base.DATABASE_URL);
    expect(env.PORT).toBe(8080);
    expect(env.API_PREFIX).toBe('/v1');
    expect(env.CORS_ORIGINS).toEqual([]);
    expect(env.THROTTLE_LIMIT).toBe(300);
    expect(env.NODE_ENV).toBe('development');
    expect(env.JWT_ACCESS_TTL_SECONDS).toBe(900);
    expect(env.EMAIL_VERIFICATION_REQUIRED).toBe(false);
    expect(env.SMTP_HOST).toBe('');
  });

  it('coerces string numbers and parses the CORS allow-list', () => {
    const env = validateEnv({
      ...base,
      PORT: '9000',
      THROTTLE_LIMIT: '100',
      THROTTLE_TTL_SECONDS: '15',
      CORS_ORIGINS: ' https://app.finflow.example.com , https://web.example.com ',
    });
    expect(env.PORT).toBe(9000);
    expect(env.THROTTLE_LIMIT).toBe(100);
    expect(env.THROTTLE_TTL_SECONDS).toBe(15);
    expect(env.CORS_ORIGINS).toEqual([
      'https://app.finflow.example.com',
      'https://web.example.com',
    ]);
  });

  it('throws with a readable message when DATABASE_URL is missing', () => {
    expect(() => validateEnv({ PORT: '8080', JWT_ACCESS_SECRET: 'x'.repeat(40) })).toThrow(
      /DATABASE_URL/,
    );
  });

  it('requires a strong JWT_ACCESS_SECRET', () => {
    expect(() => validateEnv({ ...base, JWT_ACCESS_SECRET: 'short' })).toThrow(
      /JWT_ACCESS_SECRET/,
    );
  });

  it('rejects EMAIL_VERIFICATION_REQUIRED=true without SMTP', () => {
    expect(() =>
      validateEnv({ ...base, EMAIL_VERIFICATION_REQUIRED: 'true' }),
    ).toThrow(/SMTP_HOST/);
  });

  it('accepts verification enabled when SMTP is configured', () => {
    const env = validateEnv({
      ...base,
      EMAIL_VERIFICATION_REQUIRED: 'true',
      SMTP_HOST: 'smtp.example.com',
    });
    expect(env.EMAIL_VERIFICATION_REQUIRED).toBe(true);
    expect(env.SMTP_HOST).toBe('smtp.example.com');
  });

  it('throws on a non-numeric PORT and an unknown NODE_ENV', () => {
    expect(() => validateEnv({ ...base, PORT: 'not-a-port' })).toThrow(
      /Invalid environment configuration/,
    );
    expect(() => validateEnv({ ...base, NODE_ENV: 'staging' })).toThrow(
      /NODE_ENV/,
    );
  });
});
