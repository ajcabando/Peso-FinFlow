# FinFlow API (`server/`)

Self-hosted backend for FinFlow — the local-first personal finance app. Built
with **NestJS**, **Drizzle ORM** and **PostgreSQL**. Design and contract:
`docs/SELF_HOSTED.md` and `docs/BACKEND_API.md` (project root).

## Quick start (local dev)

```sh
cp .env.example .env            # fill DATABASE_URL (+ compose secrets)
npm install
npm run db:generate             # write migrations from the schema (already committed)
npm run db:migrate              # apply migrations (needs a running Postgres)
npm run start:dev               # http://localhost:8080/health
```

## Scripts

| Script | What it does |
|---|---|
| `npm run start:dev` | Watch mode dev server |
| `npm run build` / `start:prod` | Compile to `dist/` / run compiled |
| `npm run db:generate` | `drizzle-kit` diff → new SQL migration in `src/drizzle/migrations/` |
| `npm run db:migrate` | Apply pending migrations (tsx, no build needed) |
| `npm run db:push` | Dev-only: sync schema directly (no migration file) |
| `npm test` | Unit tests (jest, `src/**/*.spec.ts`) |
| `npm run test:e2e` | API tests (supertest, `test/*.e2e-spec.ts`, DB faked) |

## Docker

The whole stack (postgres, minio, redis, migrate, finflow-api) runs from the
project root:

```sh
cd ..                      # project root
cp .env.example .env       # compose secrets (POSTGRES_*, MINIO_ROOT_*)
docker compose up -d --build
curl http://127.0.0.1:8080/health
```

See `docs/SELF_HOSTED.md` §3 for the topology (only the API is reachable;
PostgreSQL/MinIO/Redis stay on an internal network).

## Conventions

- Strict TypeScript, DTO validation via class-validator, uniform error
  envelope (`docs/BACKEND_API.md` §1).
- Migrations are generated from `src/drizzle/schema.ts` — never hand-edit
  `src/drizzle/migrations/`.
- No plaintext secrets anywhere; `.env` is gitignored.
