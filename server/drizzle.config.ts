import 'dotenv/config';
import { defineConfig } from 'drizzle-kit';

/**
 * drizzle-kit configuration.
 *  - `npm run db:generate` — diff the schema and write SQL migrations to
 *    src/drizzle/migrations/ (versioned, committed).
 *  - `npm run db:push` — dev-only: sync the schema directly (no migrations).
 *  - `npm run db:studio` — browse the database.
 *
 * `generate` never connects to PostgreSQL, so a missing DATABASE_URL is fine;
 * push/studio require a live database via DATABASE_URL.
 */
export default defineConfig({
  dialect: 'postgresql',
  schema: './src/drizzle/schema.ts',
  out: './src/drizzle/migrations',
  dbCredentials: {
    url: process.env.DATABASE_URL ?? 'postgres://localhost:5432/finflow',
  },
  strict: true,
  verbose: true,
});
