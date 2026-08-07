import { Module, ValidationPipe } from '@nestjs/common';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { APP_FILTER, APP_GUARD, APP_PIPE } from '@nestjs/core';
import { ThrottlerGuard, ThrottlerModule } from '@nestjs/throttler';
import { randomUUID } from 'node:crypto';
import { LoggerModule } from 'nestjs-pino';
import { AttachmentsModule } from './attachments/attachments.module';
import { AuthModule } from './auth/auth.module';
import { BackupsModule } from './backups/backups.module';
import { AllExceptionsFilter } from './common/filters/all-exceptions.filter';
import { validateEnv } from './config/env.validation';
import { DatabaseModule } from './database/database.module';
import { StorageModule } from './storage/storage.module';
import { DevicesModule } from './devices/devices.module';
import { HealthModule } from './health/health.module';
import { LedgerModule } from './ledger/ledger.module';
import { MailModule } from './mail/mail.module';
import { ResourcesModule } from './resources/resources.module';
import { SyncModule } from './sync/sync.module';
import { UsersModule } from './users/users.module';

@Module({
  imports: [
    // .env parsing + validation — boots or dies fast.
    ConfigModule.forRoot({ isGlobal: true, validate: validateEnv }),

    // Structured JSON logging with per-request ids (X-Request-Id).
    LoggerModule.forRootAsync({
      inject: [ConfigService],
      useFactory: (config: ConfigService) => ({
        pinoHttp: {
          level: config.get<string>('LOG_LEVEL', 'info'),
          // Phase 8 hardening: credentials, bearer tokens and refresh tokens
          // must never land in structured logs.
          redact: {
            paths: [
              'req.headers.authorization',
              'req.headers.cookie',
              'req.body.password',
              'req.body.refreshToken',
              'req.body.token',
              '*.password',
              '*.refreshToken',
            ],
          },
          // Reset/verification tokens can travel in URL query strings — strip
          // them from the logged URL, and drop auth headers defensively.
          serializers: {
            req(req) {
              const headers = { ...req.headers };
              delete headers.authorization;
              delete headers.cookie;
              const [url] = String(req.url ?? '').split('?');
              return {
                // Keep the genReqId correlation id — dropping it would sever
                // the req line from its res line and other logs.
                id: req.id,
                method: req.method,
                url,
                headers,
                remoteAddress: req.remoteAddress,
                remotePort: req.remotePort,
              };
            },
          },
          genReqId: (req, res) => {
            const existing = req.headers['x-request-id'];
            const id = Array.isArray(existing) ? existing[0] : existing;
            const generated = id || randomUUID();
            res.setHeader('X-Request-Id', generated);
            return generated;
          },
          // Pretty-print locally, structured JSON everywhere else (Docker).
          ...(config.get<string>('NODE_ENV') === 'development'
            ? { transport: { target: 'pino-pretty', options: { colorize: true } } }
            : {}),
        },
      }),
    }),

    // Global rate limiting. TTL is configured in seconds and converted to ms
    // (@nestjs/throttler v5+ expects milliseconds).
    ThrottlerModule.forRootAsync({
      inject: [ConfigService],
      useFactory: (config: ConfigService) => [
        {
          ttl: config.get<number>('THROTTLE_TTL_SECONDS', 60) * 1000,
          limit: config.get<number>('THROTTLE_LIMIT', 300),
        },
      ],
    }),

    DatabaseModule,
    HealthModule,
    UsersModule,
    MailModule,
    AuthModule,
    DevicesModule,
    SyncModule,
    StorageModule,
    AttachmentsModule,
    BackupsModule,
    ResourcesModule,
    LedgerModule,
  ],
  providers: [
    { provide: APP_GUARD, useClass: ThrottlerGuard },
    // Registered via DI (not main.ts) so e2e tests exercise the real paths.
    { provide: APP_FILTER, useClass: AllExceptionsFilter },
    {
      provide: APP_PIPE,
      useValue: new ValidationPipe({
        whitelist: true,
        transform: true,
        forbidNonWhitelisted: true,
      }),
    },
  ],
})
export class AppModule {}
