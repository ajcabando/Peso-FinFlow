import { ConfigService } from '@nestjs/config';
import { NestExpressApplication } from '@nestjs/platform-express';

/**
 * Max JSON request body. Sync push batches may carry up to 500 full entity
 * payloads (a transaction with its ledger children is several KB), which
 * easily exceeds body-parser's default 100kb — so the default must be raised
 * everywhere the app is bootstrapped (production AND tests).
 */
export const MAX_BODY_BYTES = '2mb';

/**
 * Bootstrap wiring shared by `main.ts` and the e2e harness so tests exercise
 * the exact same HTTP surface as production.
 */
export function configureApp(app: NestExpressApplication): void {
  // Sync push batches carry up to 500 full entity payloads — well beyond the
  // 100kb body-parser default.
  app.useBodyParser('json', { limit: MAX_BODY_BYTES });
  const config = app.get(ConfigService);
  const prefix = config.getOrThrow<string>('API_PREFIX');
  // Health endpoints stay at the root for nginx/Docker healthchecks.
  app.setGlobalPrefix(prefix, { exclude: ['health', 'health/(.*)'] });
}
