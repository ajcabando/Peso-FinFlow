import 'reflect-metadata';
import { Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { NestFactory } from '@nestjs/core';
import { NestExpressApplication } from '@nestjs/platform-express';
import helmet from 'helmet';
import { Logger as PinoLogger, LoggerErrorInterceptor } from 'nestjs-pino';
import { configureApp } from './app.setup';
import { AppModule } from './app.module';

async function bootstrap(): Promise<void> {
  const app = await NestFactory.create<NestExpressApplication>(AppModule, {
    bufferLogs: true,
  });

  // pino is the application logger (ConfigModule already validated env).
  app.useLogger(app.get(PinoLogger));
  app.use(helmet());

  const config = app.get(ConfigService);
  const prefix = config.getOrThrow<string>('API_PREFIX');
  configureApp(app);

  const corsOrigins = config.get<string[]>('CORS_ORIGINS', []);
  if (corsOrigins.length > 0) {
    app.enableCors({
      origin: corsOrigins,
      credentials: true,
      methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
    });
  }

  // Global validation pipe, exception filter and throttler are registered in
  // AppModule via DI (APP_PIPE / APP_FILTER / APP_GUARD) so tests exercise
  // the exact same pipeline as production.

  app.useGlobalInterceptors(new LoggerErrorInterceptor());
  app.enableShutdownHooks();

  const port = config.get<number>('PORT', 8080);
  await app.listen(port);
  Logger.log(
    `FinFlow API ready — http://localhost:${port}${prefix} (NODE_ENV=${process.env.NODE_ENV})`,
    'Bootstrap',
  );
}

void bootstrap();
