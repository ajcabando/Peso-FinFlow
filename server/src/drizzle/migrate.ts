/**
 * Standalone migration runner — applies every pending Drizzle migration.
 *
 * Used by the `migrate` Docker Compose service (`node dist/drizzle/migrate.js`)
 * and locally via `npm run db:migrate` (tsx). It intentionally has no Nest
 * dependency so it boots in seconds and fails loudly.
 */
import 'dotenv/config';
import { drizzle } from 'drizzle-orm/node-postgres';
import { migrate } from 'drizzle-orm/node-postgres/migrator';
import { join } from 'node:path';
import { Pool } from 'pg';

async function run(): Promise<void> {
  const url = process.env.DATABASE_URL;
  if (!url) {
    console.error('DATABASE_URL is not set — cannot run migrations.');
    process.exit(1);
  }

  const pool = new Pool({ connectionString: url, max: 1 });
  const db = drizzle(pool);
  // Compiled: dist/drizzle/migrate.js → dist/drizzle/migrations (copied by the
  // Dockerfile). Dev (tsx): src/drizzle/migrate.ts → src/drizzle/migrations.
  const migrationsFolder = join(__dirname, 'migrations');

  console.log(`Applying migrations from ${migrationsFolder} …`);
  await migrate(db, { migrationsFolder });
  console.log('Migrations applied.');
  await pool.end();
}

run().catch((error) => {
  console.error('Migration failed:', error);
  process.exit(1);
});
