# FinFlow — Database Design & the Double-Entry Ledger

SQLite via Drift. Schema version **2**. Every monetary value is an **integer in
minor units** (e.g. `12345` = ₱123.45); currency decimal digits are handled by
`CurrencyFormatter` (JPY=0, BHD=3, default 2).

## ERD

```
accounts ─────────────┐
  id (PK)             │
  name, institution   │
  kind (account|category|system)
  type (cash|bank|debitCard|creditCard|ewallet|paypal|crypto|investment|loan|
         income|expense|openingBalance)
  status, opening_balance_minor, currency_code
  color_value, icon_code, notes, sort_order, is_hidden
  created_at, updated_at
                      │
ledger_entries ───────┤            transactions ─────────────┐
  id (PK)             │              id (PK)                 │
  transaction_id (FK) │              type, amount_minor      │
  account_id (FK) ────┘              currency_code           │
  direction (debit|credit)           occurred_at, note       │
  amount_minor, currency_code        merchant, reference_no  │
                                     location, created/updated
                                                     │
tags ◄── transaction_tags ──► transactions           │
  id (PK)   (tx_id FK, tag_id FK)                     │
  name, color                                          │
                                                       │
attachments ──────────────────────────────────────────┘
  id (PK), transaction_id (FK), file_path, mime_type,
  file_size_bytes, caption, created_at

budgets ─────────────────────────────┐
  id (PK)                            │
  category_id (FK → accounts, unique)│
  amount_minor, currency_code        │
  created_at, updated_at             │

app_settings (key PK, value)
```

Indexes: `ledger_entries(account_id)`, `ledger_entries(transaction_id)`,
`transactions(occurred_at)`, `transactions(merchant)`.

## Categories are accounts

Income & expense categories are stored in the **same `accounts` table** with
`kind = category`. This is the trick that makes the whole engine uniform:
category spending is just an aggregate over the ledger, identical to account
balances.

## Normal balance sides

| Type | Normal side | Balance formula |
|---|---|---|
| cash, bank, debitCard, ewallet, paypal, crypto, investment | debit | `debits − credits` |
| creditCard, loan | credit | `credits − debits` |
| income category | credit | `credits − debits` = income earned |
| expense category | debit | `debits − credits` = money spent |
| openingBalance (system) | credit | counterpart account |

## Why balances can never corrupt

- The `accounts.opening_balance_minor` column is **informational only**. The
  authoritative starting balance is recorded as an "Opening Balance" transaction
  paired with the system *Opening Balances* account.
- Every transaction is validated by `DoubleEntryEngine` (debits == credits, ≥2
  entries, positive amounts, one entry per account) before it is written.
- Writes are atomic (single SQL transaction), so a failure cannot leave a
  half-written transaction.
- Balances are computed on demand by `LedgerDao` (`SUM ... GROUP BY account_id`)
  and mapped through each account's normal side.

## Budgets

A monthly spending limit per **expense category** (`budgets.category_id`, one
budget per category enforced by a unique key). Progress is never stored: it is
computed on demand as the category's net ledger activity (expense debits minus
refund credits) for the selected month, reusing the same aggregation as the
analytics category-spend breakdown.

## Seeding

`DatabaseSeeder` (idempotent, runs on `onCreate`) provisions:

1. The system **Opening Balances** account.
2. 32 default categories (7 income, 25 expense) matching the product spec
   (Salary, Food & Dining, Utilities, ...). Users can rename/recolour/add their
   own at any time.

## Migrations

`schemaVersion` is 2:

- **1 → 2** adds the `budgets` table (Phase 7). The `onUpgrade` step creates it
  via `m.createTable(budgets)`; existing data is preserved.

Future phases (bills, goals, credit-card cycles, security metadata) add
tables/columns through `migration` step callbacks, bumping the version.
Foreign keys are enforced (`PRAGMA foreign_keys = ON`) on every connection.

## Web persistence

On the web the same schema runs inside SQLite WASM (`web/sqlite3.wasm` +
`web/drift_worker.js`) with File System API persistence, so offline-first
behaviour is identical across platforms.
