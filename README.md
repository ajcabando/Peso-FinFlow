# FinFlow

**Know Where Every Peso Goes** — a local-first, offline-first personal finance platform for Android, iOS, iPadOS and the Web.

> Built on a **double-entry accounting engine**: every transaction is recorded as balanced debits and credits, so balances are always derived from the ledger and can never drift out of sync.

---

## Status

**Foundation (Phases 1–3) + account management (Phase 4) + transaction UI (Phase 5) + dashboard & analytics (Phase 6) + budgets (Phase 7) complete.**

| Phase | Deliverable | Status |
|-------|-------------|--------|
| 1 | Project setup, clean architecture, DI (Riverpod), routing (go_router) | ✅ |
| 2 | Material 3 design system — light/dark themes, tokens, reusable components | ✅ |
| 3 | Drift (SQLite) local database + double-entry ledger schema, engine, repositories | ✅ |
| 4 | Account management: detail page, edit, archive, delete (guarded), per-account activity | ✅ |
| 5 | Transaction engine UI: expense/income/transfer/refund entry, full list with search & filters | ✅ |
| 6 | Dashboard & analytics: category spend (donut + ranked list), net worth history, analytics page with month picker | ✅ |
| 7 | Budgets & goals: monthly per-category budgets with ledger-derived progress, budgets page + dashboard overview | ✅ |
| 8–15 | Bills & reminders, reports, backup, security, AI, cloud sync | ⏳ Next phases |

Validation: `flutter analyze` clean · **101 tests passing** (unit + integration + widget) · web build compiles.

---

## Quick start

```bash
# Requires Flutter 3.44+ (installed at ~/flutter on this machine)
export PATH="$HOME/flutter/bin:$PATH"
flutter pub get
dart run build_runner build          # generates Drift code
flutter run                          # Android / iOS / desktop
flutter run -d chrome                # or web
flutter test                         # run the test suite
flutter analyze                      # lint
```

### Web build

The web target ships a SQLite WASM build (`web/sqlite3.wasm` + `web/drift_worker.js`) so the database runs fully in the browser with File System API persistence. Build with `flutter build web` and serve the `build/web` directory.

---

## Architecture

```
lib/
├── main.dart                     # entry point
├── app/                          # composition root
│   ├── app.dart                  # MaterialApp.router + themes
│   ├── router/app_router.dart    # go_router navigation tree
│   └── providers/                # Riverpod: DB, repositories, theme, currency
├── core/                         # cross-cutting concerns
│   ├── constants/  errors/  utils/  extensions/  theme/
├── database/                     # Drift: tables, DAOs, seeder, connection
├── shared/widgets/               # design-system components
└── features/                     # feature-first modules
    ├── accounts/                 # domain / data / presentation
    ├── transactions/             # domain / data (UI in a later phase)
    ├── dashboard/  settings/
```

Dependency flow: **presentation → domain ← data → database → core**. Business rules
live in pure-Dart domain classes (the double-entry engine has zero Flutter or
database imports); repositories are the single write path and enforce atomicity.

See [`docs/architecture.md`](docs/architecture.md) and [`docs/database.md`](docs/database.md).

---

## The accounting engine

Every transaction produces **balanced ledger entries** (sum of debits = sum of credits):

| Event | Debit | Credit |
|---|---|---|
| Expense (₱500 cash) | Food & Dining 500 | Cash 500 |
| Income (₱30,000 salary) | Bank 30,000 | Salary 30,000 |
| Cash → GCash transfer ₱1,000 | GCash 1,000 | Cash 1,000 |
| Credit card purchase ₱2,000 | Groceries 2,000 | Credit Card 2,000 |
| Credit card payment ₱2,000 | Credit Card 2,000 | Bank 2,000 |
| Account opening ₱5,000 | Account 5,000 | Opening Balances 5,000 |

Balances are **derived, never stored**: debit-normal accounts (cash, bank, expense
categories) = debits − credits; credit-normal accounts (credit cards, income
categories) = credits − debits. Because the ledger is the only source of truth,
balance corruption is structurally impossible — and transfers & credit cards can
never be double-counted.

---

## What works today

- **Dashboard** — animated Net Worth hero (assets − liabilities), quick actions, monthly cash flow chart, current-month spending by category, recent activity feed with "View all".
- **Analytics** — dedicated page with a month picker: 12-month net worth history line chart, spending & income breakdowns by category (tappable donut charts with ranked lists).
- **Budgets** — monthly limit per expense category with progress tracked straight from the ledger (refunds included); budgets page with month picker, budgeted/spent/left summary, over-budget highlighting, plus a dashboard overview with the top at-risk budgets.
- **Transactions** — add expense / income / transfer / refund with date & time pickers, accounts, categories, merchant and notes; full transaction list with instant search and type filters.
- **Accounts** — create (cash, bank, debit/credit card, e-wallet, PayPal, crypto, investment, loan) with opening balances recorded as balanced ledger transactions; detail page with balance, info, per-account activity, edit / archive / delete (guarded).
- **Settings** — theme (system/light/dark, persisted), default currency.
- **Data model ready** — transactions, ledger, tags, attachments, settings tables with the full double-entry plumbing (validation, atomic writes, reactive streams, semantic type rules).

## Roadmap (from the master plan)

4. Account management (edit, archive, icons, balance history)
5. Transaction engine UI (income/expense/transfer/refund entry)
6. Dashboard & analytics (charts: cash flow, net worth, category spend)
7. Budgets & goals
8. Bills & reminders
9. Reports & exports (PDF/Excel/CSV)
10. Backup & restore
11. Security (PIN, biometrics, encryption)
12. AI insights
13. Optional cloud sync
14. Performance (million-transaction stress)
15. Release hardening
