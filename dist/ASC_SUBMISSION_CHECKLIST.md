# Peso-FinFlow — App Store Connect Submission Checklist

App record: **Peso-FinFlow** · Version **0.1.0** · Build **6** (Delivery UUID `e7d27ac4-4d29-401f-bac4-23b31d8f73bf`)

Assets prepped: **`dist/Peso-FinFlow-ASC-assets.zip`** (8 screenshots + 1024px icon).

---

## 1. Confirm build 6 is ready
- Open https://appstoreconnect.apple.com → **TestFlight → iOS builds**
- Build **0.1.0 (6)** should show **Processing → Ready to Test** (allow ~10–30 min after upload)
- ⚠️ Delete stale builds 2–5 to avoid confusion (TestFlight → build row → ⋯ → Remove)

## 2. Fill in the app version metadata
App Store Connect → **Apps → Peso-FinFlow → iOS App → Version 0.1.0 (Prepare for Submission)**

| Field | Suggested value |
|---|---|
| Promotional text | Know where every peso goes. (optional) |
| Description | Local-first personal finance for the Philippines. Track income & expenses with a true double-entry engine — every transaction balances automatically, and your account balances, budgets, and reports stay in sync. Works fully offline; your data never leaves your device. Includes PIN + Face ID lock, recurring bills, monthly reports (PDF/CSV), and one-tap backup. |
| What's New | First release: double-entry ledger, budgets, analytics, recurring bills, PIN/Face ID security, PDF/CSV reports, and portable backup. |
| Keywords | finance, budget, peso, philippines, money, expenses, ledger, bills, savings, tracker |
| Support URL | (your site / a page you own — required) |
| Marketing URL | optional |
| Copyright | © 2026 Alain Cabando |
| Age Rating | 4+ (no objectionable content). Complete the quiz: no violence, no sexual content, no profanity. |
| Privacy Policy URL | (required before review — must be a live https URL) |

## 3. Upload screenshots
- App Store Connect → **App Preview & Screenshots** section
- **6.7″ iPhone** (1290×2796): upload `iphone-6.7-dashboard.png`, `iphone-6.7-analytics.png`, `iphone-6.7-transactions.png`, `iphone-6.7-accounts.png`
- **12.9″ iPad Pro** (2048×2732): upload the 4 `ipad-12.9-*.png` files
- These exact sizes are already correct — drag & drop, no resizing needed.

## 4. App icon
- App Store Connect → **App Icon** → upload `app-icon-1024.png` (from the zip)
- (Icon is also embedded in build 6, but ASC wants the 1024px marketing copy too.)

## 5. Privacy answers (required before review)
App Store Connect → **App Privacy → Data Collection**
- **"No Data Collected"** — FinFlow is local-first; nothing leaves the device.
  - If any analytics/crash reporting is added later, revisit this.
- **Sensitive info:** Face ID — add a note: "Used to unlock the app locally with biometrics; not transmitted."

## 6. Version info quirks
- **Export Compliance**: `ITSAppUsesNonExemptEncryption = false` is already in Info.plist → answer **No** to the encryption question.
- **ATT prompt**: not used (no ads/tracking) → nothing to configure.

## 7. Submit
- Click **Add for Review** → answer the "Export Compliance" (No) + "Content Rights" (Yes) questions → **Submit**.
- First reviews take **24–72 hours**.

## Troubleshooting
- Build 6 missing in TestFlight → wait 30 min; if still gone, check **Activity** tab for processing errors.
- Screenshot rejected → make sure the PNG has no alpha channel and exact size (both already true).
- Need a privacy policy URL? A one-page https site (e.g., GitHub Pages / Notion public page) with a statement "Peso-FinFlow stores all data locally on your device and does not collect or transmit personal data" is enough for review.
