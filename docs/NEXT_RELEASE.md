# Peso-FinFlow v0.2.0 — Next Release Plan

Version: `0.2.0+1` (bumped 2026-08-06, after v0.1.0 (6) shipped to App Store Connect).

## Goals
1. **First post-launch iteration** — ship real user-facing value on top of the solid double-entry core.
2. **Grow the installed base** via the features testers/early users ask for first (money in → money out → recurring → insights).
3. **Keep the local-first promise** — no accounts, no servers, no data collection.

## Feature candidates (priority order)

### P0 — must-have for v0.2.0
| Feature | Why | Notes |
|---|---|---|
| **Multi-currency support** | Core gap: FinFlow is Peso-first but a finance app should handle USD/EUR savings, travel, and crypto. | Store `currency_code` on accounts; ledger stays integer-minor but per-account; CurrencyFormatter already supports JPY=0/BHD=3 decimal digits. Needs a settings default currency + per-account override. |
| **Transaction editing UX** | Currently edit is possible; polish: swipe-to-edit/delete consistency, batch delete, undo snackbar. | Undo = reverse via a compensating double-entry transaction (auditable), not hard delete. |
| **Scheduled/standing transactions** | Recurring bills exist; extend to recurring income and recurring transfers with a "post now" action. | Reuse `bills` table or add `schedules` table; schema v3 migration. |

### P1 — strong candidates
| Feature | Why | Notes |
|---|---|---|
| **Search + filter improvements** | Saved filter presets, date-range presets, amount-range filter. | Purely additive to existing windowed `transactionsPage`. |
| **Report enhancements** | YTD report, category trends over N months, export to Google Sheets-friendly CSV. | Existing CSV/PDF exporter extends. |
| **Budget rollover / yearly budgets** | Carry unused budget to next month (or don't) per category. | New settings + budget model field. |
| **Widget (iOS home screen / Android)** | Net worth + cash flow glanceable widget. | Needs `ios_widget` (Swift) or `home_widget` package — native work. |

### P2 — backlog / post-1.0 stretch
| Feature | Why | Notes |
|---|---|---|
| **AI insights** (deferred Phase 12) | Spend anomaly detection, natural-language questions ("how much did I spend on food in March?"). | Needs a provider key + privacy story (on-device model or user-opt-in cloud). Revisit with on-device LLM if feasible. |
| **Optional cloud sync** (deferred Phase 13) | Multi-device. | Conflicts with local-first; would use user-provided storage (iCloud Drive file sync or WebDAV) rather than a server. |
| **Shared budgets (family)** | Household spending. | Multi-user is a big architectural change; park it. |
| **Macro/CSV import** | Bank statement import. | High value in PH (bank CSVs); medium effort. |

## Suggested v0.2.0 scope (MVP cut)
1. Multi-currency accounts + default currency setting
2. Undo (compensating entry) + swipe-action polish
3. Recurring income/transfers (schedules) with "post now"
4. YTD report + category trends
5. Home-screen widget (if time allows — otherwise moves to v0.3.0)

## Process
- Keep `flutter analyze` clean and the suite (180+ tests) green per change.
- Schema v3 (schedules, currency_code, budget rollover) needs: table changes → `dart run build_runner build` → migration step in `AppDatabase` → version bump.
- Tag `v0.2.0` + update `docs/BUILDING.md` artifacts (`dist/`) once cut.
- New App Store build: `0.2.0 (1)`; keep the ASC API tooling (`tool/asc_api.py`) for watch/upload status.

## Deferred explicitly (not in v0.2.0)
- Cloud sync, AI insights, family sharing, bank feed integration.
