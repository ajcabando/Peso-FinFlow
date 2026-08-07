# Peso-FinFlow — App Store Connect Submission Checklist (go-live state, 2026-08-06)

App record: **Peso-FinFlow** · Version **0.1.0** · Build **6** (Delivery UUID `e7d27ac4-4d29-401f-bac4-23b31d8f73bf`, VALID, expires 2026-11-04)

Repo: **public** · Privacy policy **live** at https://ajcabando.github.io/FinFlow/privacy-policy.html (HTTP 200)

---

## ✅ Already done (via ASC API — verified)

| Item | Status |
|---|---|
| Build 6 attached to iOS version 0.1.0 (`PREPARE_FOR_SUBMISSION`) | ✅ |
| Version string aligned (was "1.0" → "0.1.0") | ✅ |
| Description, keywords (93 chars), promotional text, support URL | ✅ |
| App name (Peso-FinFlow), subtitle, **privacy policy URL** | ✅ |
| Age rating 4+ (nothing flagged) | ✅ |
| Screenshots: 4× iPhone 6.7″ + 4× iPad 12.9″ | ✅ |
| Export compliance `usesNonExemptEncryption = false` | ✅ |

## 📋 Remaining manual steps (ASC web UI only — ~5 minutes)

Open https://appstoreconnect.apple.com → **Apps → Peso-FinFlow → iOS App → Version 0.1.0**

1. **App Privacy → Data Collection** — select **"No Data Collected"** (FinFlow is local-first; nothing leaves the device). If prompted about Face ID, note: *"Used only to unlock the app locally with biometrics; never stored or transmitted."*
2. **App Review → App Review Information** — add contact name, phone, email (reviewer contact; not shown publicly). Optional notes: demo-account not applicable.
3. *(Optional)* **What's New** — not required for a first release. If you want it: "First release: double-entry ledger, budgets, analytics, recurring bills, PIN/Face ID security, PDF/CSV reports, and portable backup."
4. *(Optional housekeeping)* **TestFlight → iOS builds** — remove stale builds 2–5 to avoid confusion.
5. **Add for Review / Submit for Review** — answer **Export Compliance: No** and **Content Rights: Yes** (you hold the rights), then submit.
6. First review takes **24–72 hours**. Watch status with `python3 tool/asc_api.py detail <build_id>` or the ASC portal.

## Notes
- The app icon (1024px) is embedded in build 6; the store listing uses it automatically. `dist/Peso-FinFlow-ASC-assets.zip` still holds the 8 screenshots + icon if you ever need to re-upload.
- `whatsNew` cannot be set via the ASC API (409) — UI only, and optional for the first release.
- Programmatic "Submit for Review" does not exist (Apple removed it in 2023) — the final click must be done in the web UI.
