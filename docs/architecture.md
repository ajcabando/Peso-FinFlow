# FinFlow — System Architecture

## 1. Design principles

- **Local-first / offline-first.** The app is fully functional with no network.
  All data lives in a SQLite database on the device. Cloud sync (Phase 13) will
  be an *optional* module layered on top, not a requirement.
- **Clean architecture, feature-first.** The codebase is organised by feature
  (accounts, transactions, dashboard, ...), and each feature is split into
  `domain` (pure business logic), `data` (persistence) and `presentation`
  (Flutter UI).
- **Single source of truth.** The double-entry ledger is the only place money
  movement is recorded. Account balances are *derived* aggregates — there is no
  stored "balance" field that can go stale or corrupt.
- **Dependency injection everywhere.** Riverpod's `Provider` graph is the
  composition root; every repository and DAO is provided once and consumed by
  reference, which makes tests trivial (in-memory database override).

## 2. Layering

```
presentation  ──►  domain  ◄──  data  ──►  database  ──►  core
   (widgets,       (models,        (repositories    (Drift tables,
    providers,      enums, engine,  implementing     DAOs, connection,
    pages)          use cases)      domain contracts) seeder)
```

- **Domain** keeps business logic (the double-entry engine, builders, enums,
  use cases) free of Flutter and Riverpod and fully unit-testable. Two domain
  models expose `fromRow` convenience factories that map generated persistence
  rows to domain objects — a pragmatic compromise that keeps mappers adjacent
  to the models; the accounting logic itself never touches storage.
- **Data** implements the abstract repository interfaces declared in domain,
  mapping generated DB rows to domain models and enforcing atomicity.
- **Database** owns Drift schema, migrations and seeding.
- **Core** holds shared constants, errors, utilities and the design tokens.

## 3. Dependency injection (Riverpod)

| Provider | Provides |
|---|---|
| `databaseProvider` | The single `AppDatabase` (overridden with an in-memory DB in tests) |
| `transactionRepositoryProvider` | `TransactionRepositoryImpl` |
| `accountRepositoryProvider` | `AccountRepositoryImpl` (injects the transaction repository to write opening-balance ledger entries atomically) |
| `themeModeProvider` / `defaultCurrencyProvider` | Persisted preferences backed by the `app_settings` table |
| Feature stream providers | `netWorthProvider`, `accountsWithBalancesProvider`, `recentTransactionsProvider`, ... |

All UI reads state through reactive streams (`StreamProvider`): the database
pushes changes and every screen updates automatically.

## 4. Navigation

`go_router` with a `StatefulShellRoute.indexedStack`: Dashboard, Accounts and
Settings stay alive across tab switches; the account form is pushed on top of
the Accounts branch using the root navigator key.

## 5. Error handling

All failures are `FinFlowException` subclasses (`ValidationException`,
`DomainException`, `NotFoundException`, `DatabaseException`). Repositories throw
them; the UI catches them and surfaces `message` in a snackbar — internals never
leak to the user.

## 6. Atomicity

Repositories wrap every multi-table mutation in `db.transaction(...)`:

- `createAccount` writes the account row **and** its opening-balance ledger
  transaction in one transaction.
- `TransactionRepository.create/update/delete` validate with the engine, then
  write/rewrite/remove the header, all ledger entries and tags atomically.

A crash at any point leaves the ledger in a consistent state — never unbalanced.

## 7. Performance notes (foundation)

- Ledger aggregation uses indexed `SUM` queries (`ledger_entries(account_id)`),
  so balance computation stays fast at scale.
- All lists are `Stream`-based (no polling), and queries are scoped (recent
  transactions are `LIMIT`-ed).
- Phase 14 will add windowing, pagination and a million-row stress harness.
