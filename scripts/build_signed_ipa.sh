#!/usr/bin/env bash
#
# build_signed_ipa.sh — sign FinFlow for a free Apple ID "Personal Team" and
# export a device-installable IPA.
#
# Prerequisites (one-time, done in Xcode GUI):
#   1. Xcode → Settings → Accounts → "+" → Apple ID → sign in.
#      Your Apple ID must show a "Personal Team" (plan: Free).
#   2. Connect + unlock your iPhone/iPad and tap "Trust This Computer".
#      Xcode registers it to the free development profile automatically.
#
# Free accounts re-issue profiles every 7 days — re-run this script to re-sign.
#
set -euo pipefail
cd "$(dirname "$0")/.."

# --- 1. Locate the Apple Development certificate and extract the Team ID -----
CERT_SUBJECT=$(security find-certificate -c 'Apple Development' -p 2>/dev/null | \
  openssl x509 -noout -subject 2>/dev/null || true)
if [ -z "$CERT_SUBJECT" ]; then
  echo "ERROR: no 'Apple Development' certificate found on this Mac." >&2
  echo "Add your Apple ID in Xcode → Settings → Accounts first (see prerequisites above)." >&2
  exit 1
fi
TEAM_ID=$(printf '%s' "$CERT_SUBJECT" | sed -E 's/.*OU=([A-Z0-9]{10})([,. /]|$).*/\1/')
if [ ${#TEAM_ID} -ne 10 ]; then
  echo "ERROR: could not extract a 10-character Team ID from certificate subject:" >&2
  echo "  $CERT_SUBJECT" >&2
  exit 1
fi
echo "== Team ID: $TEAM_ID"

# --- 2. Wire automatic signing into the Runner target (idempotent) -----------
PBX="ios/Runner.xcodeproj/project.pbxproj"
if grep -q "DEVELOPMENT_TEAM = $TEAM_ID;" "$PBX"; then
  echo "== DEVELOPMENT_TEAM already set in $PBX"
else
  echo "== Injecting CODE_SIGN_STYLE=Automatic + DEVELOPMENT_TEAM into Runner configs"
  perl -0pi -e \
    's/(PRODUCT_BUNDLE_IDENTIFIER = com\.finflow\.finflow;)/$1\n\t\t\t\tCODE_SIGN_STYLE = Automatic;\n\t\t\t\tDEVELOPMENT_TEAM = '"$TEAM_ID"';/g' \
    "$PBX"
  grep -c "DEVELOPMENT_TEAM = $TEAM_ID;" "$PBX" | sed 's/^/== configs patched: /'
fi

# --- 3. Build + export the signed IPA ----------------------------------------
echo "== flutter build ipa (release, development export)"
export PATH="$HOME/flutter/bin:$PATH"
flutter build ipa --release \
  --export-options-plist=ios/export_options_dev.plist

# --- 4. Stage the artifact ----------------------------------------------------
mkdir -p dist
SRC=$(ls -t build/ios/ipa/*.ipa | head -1)
DST="dist/FinFlow-signed.ipa"
cp "$SRC" "$DST"
echo "== ✅ Signed IPA: $DST"
echo "== Verify embedded profile:"
unzip -p "$DST" Payload/Runner.app/embedded.mobileprovision 2>/dev/null | \
  security cms -D 2>/dev/null | plutil -extract Name raw - 2>/dev/null || \
  echo "(profile name unavailable — install and check in Settings → General → VPN & Device Management)"
