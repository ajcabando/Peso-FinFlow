# Peso-FinFlow — App Store Connect Copy Pack

Copy-paste ready for **App Store Connect → Apps → Peso-FinFlow → iOS App → 1.0 Prepare for Submission**.

---

## App name
`Peso-FinFlow`

## Subtitle (≤ 30 chars)
`Know where every peso goes`

## Promotional text (≤ 170 chars)
`Local-first budgeting with a true double-entry ledger — balanced books, budgets, bills, and reports, all offline.`

## Description (≤ 4000 chars)
**Peso-FinFlow is a local-first personal finance app built around a real double-entry accounting engine.** Every transaction is recorded as balanced debits and credits, so your account balances are always derived from the ledger — they can never drift out of sync.

**Know where every peso goes.**
- **Accounts** — Cash, bank, debit/credit cards, e-wallets (GCash, Maya), PayPal, crypto, investments, and loans. Opening balances are recorded as balanced ledger transactions, so transfers and credit cards can never be double-counted.
- **Transactions** — Expense, income, transfer, and refund entry with categories, merchant, and notes. Search the full history and filter by type instantly.
- **Dashboard** — Net worth hero (assets minus liabilities), monthly cash flow chart, spending by category, budget overview, and a bills card — all in one glance.
- **Analytics** — A 12-month net worth history and income/spending breakdowns by category, with a month picker.
- **Budgets** — Set monthly limits per category. Progress is derived from your actual ledger, with over-budget highlighting.
- **Bills & reminders** — Recurring bills with due-day tracking, "due soon / overdue / paid" states, and one-tap mark-paid.
- **Reports & exports** — Monthly income/expense summaries with category breakdowns, exportable as CSV or a styled PDF.
- **Backup & restore** — One-tap portable snapshot of everything (accounts, transactions, ledger, budgets, bills, settings). Restore on any device.
- **Security** — Optional 4–8 digit PIN lock with Touch ID / Face ID unlock and auto-lock.

**Private by design.** Peso-FinFlow stores everything on your device. There is no account, no server, and no data collection — your finances never leave your phone.

## What's New (this release) (≤ 4000 chars)
`First release: double-entry ledger, accounts, budgets, analytics, recurring bills, monthly reports (PDF/CSV), portable backup, and PIN/Face ID security — all fully offline.`

## Keywords (≤ 100 chars, comma-separated, no spaces needed)
`finance,budget,peso,philippines,ph,money,expenses,ledger,expense tracker,bills,spending,savings,gcash,maya,bank,wallet`

## App icon
Upload `dist/asc-upload/app-icon-1024.png` (also in `Peso-FinFlow-ASC-assets.zip`).

## Support URL
https://github.com/ajcabando/FinFlow (repo has README + issue tracker)

## Marketing URL (optional)
https://github.com/ajcabando/FinFlow

## Copyright
`© 2026 Alain Cabando`

## Age rating
Answer the questionnaire honestly:
- **4+** — no objectionable content, no user-generated content, no gambling, no unprotected web access beyond links.

## Screenshots
Upload from `dist/Peso-FinFlow-ASC-assets.zip`:
- **6.7″ iPhone** (1290×2796): `iphone-6.7-dashboard.png`, `iphone-6.7-analytics.png`, `iphone-6.7-transactions.png`, `iphone-6.7-accounts.png`
- **12.9″ iPad Pro** (2048×2732): the four `ipad-12.9-*.png` files

## Privacy answers (App Privacy → Data Collection)
Select **"No Data Collected"**.
- No analytics, no crash reporting, no ads, no tracking, no third-party SDKs that collect data.
- Data types screen: everything **not collected**.
- **Face ID** (optional local unlock) is a device capability — covered by "No Data Collected" since biometrics never leave the device. If ASC asks, note it under "Sensitive Info": *Used only to unlock the app locally; never stored or transmitted.*

## Export Compliance
`ITSAppUsesNonExemptEncryption` is already **false** in the build (verified via API: `usesNonExemptEncryption = False`). Answer **No** to "Does your app use encryption?" (no encryption beyond standard HTTPS to nothing — the app is fully offline).

## Version info
- Version `0.1.0` · Build `6` (VALID on ASC, expires 2026-11-04)

---

## Privacy policy (host this file)
Use `dist/privacy-policy.html` (included in this pack) — host it on GitHub Pages:
1. Push `privacy-policy.html` to a repo (e.g. `ajcabando/FinFlow` branch `gh-pages`, or any GitHub repo's `docs/` folder with Pages enabled).
2. URL becomes e.g. `https://ajcabando.github.io/FinFlow/privacy-policy.html`
3. Paste that URL into the **Privacy Policy URL** field.
