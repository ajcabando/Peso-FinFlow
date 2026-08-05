# Building FinFlow — release artifacts

This guide covers producing installable artifacts for every platform.

**Toolchain status on this machine (as of 2026-08-05):**

| Platform | Toolchain | Status |
|---|---|---|
| Web | Flutter only | ✅ `flutter build web` |
| Android | JDK 21 (Homebrew) + Android SDK 36 at `~/Library/Android/sdk` | ✅ APK builds |
| macOS (DMG) | Xcode 26.6 at `/Volumes/DATA/Applications/Xcode.app` + CocoaPods 1.17 | ✅ DMG builds |
| iOS (app/IPA) | Xcode 26.6 + iOS 26.5 SDK | ✅ unsigned; signed via free Apple ID script |

**Gotcha — Xcode lives on the DATA volume.** The machine's active developer directory must be pointed at it once (this was the whole battle):

```bash
sudo xcode-select -s /Volumes/DATA/Applications/Xcode.app/Contents/Developer
```

If `xcrun --show-sdk-path --sdk iphoneos` fails, the switch got reset — re-run it. The iOS 26.5 platform was installed with `xcodebuild -downloadPlatform iOS` (it is not bundled with Xcode 26.6 by default).

All builds assume:

```bash
export PATH="$HOME/flutter/bin:$PATH"
# Android builds also need JDK 17+ (JDK 21 installed via Homebrew):
export JAVA_HOME=/opt/homebrew/opt/openjdk@21
export PATH="$JAVA_HOME/bin:$PATH"
```

---

## Android — release APK

The toolchain is already set up on this machine (`android/local.properties` points at
`~/Library/Android/sdk`; `sdkmanager` accepted all licenses). Rebuild anytime with:

```bash
flutter build apk --release
# → build/app/outputs/flutter-apk/app-release.apk
```

A copy with a versioned name lives at `dist/FinFlow-v0.1.0.apk` (signed, verified with `apksigner`).

> **Signing note:** `android/app/build.gradle.kts` currently signs *release* builds with the
> **debug** keystore (the stock Flutter template default). That's fine for sideloading and testing.
> For Play Store / wider distribution, generate a real release keystore:
>
> ```bash
> keytool -genkey -v -keystore ~/.android/finflow-release.jks -keyalg RSA \
>   -keysize 2048 -validity 10000 -alias finflow
> ```
>
> then wire it into `android/app/build.gradle.kts` (a `signingConfigs.release` block with
> `storeFile`/`storePassword`/`keyAlias`/`keyPassword` from `~/.gradle/gradle.properties`
> or env vars — never commit secrets).

To install on a connected device/emulator:

```bash
adb install -r dist/FinFlow-v0.1.0.apk
```

---

## macOS — DMG

Requires **Xcode** (see [Installing Xcode](#installing-xcode) below). Once installed:

```bash
# 1. Build the .app bundle
flutter build macos --release
# → build/macos/Build/Products/Release/FinFlow.app

# 2. Package a DMG. Two options:

# Option A — quick, plain DMG (no drag-drop layout):
hdiutil create -volname FinFlow -srcfolder \
  build/macos/Build/Products/Release/FinFlow.app \
  -ov -format UDZO dist/FinFlow-v0.1.0.dmg

# Option B — nice drag-drop install DMG with /Applications symlink:
# (brew install --cask create-dmg first)
create-dmg \
  --volname "FinFlow v0.1.0" \
  --window-pos 200 120 --window-size 600 400 \
  --icon-size 100 --icon "FinFlow.app" 175 190 \
  --hide-extension "FinFlow.app" --app-drop-link 425 190 \
  dist/FinFlow-v0.1.0.dmg \
  build/macos/Build/Products/Release/FinFlow.app
```

> **Status:** built and validated — `dist/FinFlow-v0.1.0.dmg` (mounts, contains `finflow.app` + `/Applications` drag target).
>
> **Signing note:** `flutter build macos --release` ad-hoc signs. For distribution to other
> Macs you need Developer ID signing + notarization (`xcrun notarytool submit`), which requires
> an Apple Developer account. The DMG itself is fine for local installs.

---

## iOS — .app / IPA

Requires **Xcode** and an Apple signing identity (free Apple ID works for personal devices —
the project is already configured with `NSFaceIDUsageDescription` and a bundle id).

```bash
# Unsigned build (no Apple account — for CI or ad-hoc testing):
flutter build ios --release --no-codesign
# → build/ios/iphoneos/Runner.app  (works with tools like applesign, or simulator)
```

### Signed IPA with a free Apple ID (Personal Team)

This is the path for installing on your own iPhone/iPad without paying Apple. The
project's Runner target does **not** ship with a `DEVELOPMENT_TEAM`, so signing is
wired in automatically by `scripts/build_signed_ipa.sh` (it reads the Team ID from
your installed `Apple Development` certificate and patches `project.pbxproj`
idempotently).

**One-time manual prerequisites (must be done on this Mac, in the Xcode GUI):**

1. **Xcode → Settings… (`⌘,`) → Accounts → `+` → Apple ID → sign in.**
   Your Apple ID must show a **"Personal Team"** underneath it (plan: Free).
   If you see *"An unexpected error occurred"*, restart Xcode and retry, or sign in
   once at appleid.apple.com first.
2. **Plug in your iPhone/iPad, unlock it, tap "Trust This Computer".** Xcode
   registers the device to the free profile automatically.

Then build — everything after step 1–2 is automated:

```bash
scripts/build_signed_ipa.sh
# → dist/FinFlow-signed.ipa  (development-signed, device-installable)
```

Install over USB or via AirDrop/email:

```bash
xcrun devicectl device install app --device <UDID> dist/FinFlow-signed.ipa
# or: open in Finder → drag onto your device in Finder → accept on the phone
```

Then on the phone: **Settings → General → VPN & Device Management → trust your Apple ID**
the first time.

> **⚠️ Free-account constraints**
> - The development provisioning profile **expires after 7 days** — re-run
>   `scripts/build_signed_ipa.sh` to re-sign whenever the app stops launching.
> - Free teams get **no push notifications, iCloud, App Groups, etc.** — FinFlow doesn't
>   use any of these, so nothing is lost.
> - The bundle id must be **globally unique**. `com.finflow.finflow` is very generic and
>   may already be registered by another developer — if the build fails with *"An App ID
>   with identifier 'com.finflow.finflow' is not available"*, switch it to a unique id
>   (e.g. `com.ajcabando.finflow`) in the three Runner configs of `project.pbxproj`.

> **Status:** unsigned `dist/FinFlow-v0.1.0.ipa` already built and validated. The app is
> **universal**: `UIDeviceFamily = [1, 2]` so the same artifact runs on both **iPhone and
> iPad** (iPadOS needs no separate build). The signed build requires the Apple ID
> prerequisites above (an account present in Xcode + a registered device).

If you only need to smoke-test on a simulator:

```bash
flutter build ios --simulator
```

---

## Installing Xcode (the missing piece)

1. **Install Xcode** — open the App Store, search "Xcode", install (~12 GB). Or download from
   https://developer.apple.com/xcode/ (requires an Apple ID).
2. **Point the toolchain at it** and accept the license:
   ```bash
   sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
   sudo xcodebuild -license accept
   xcodebuild -runFirstLaunch
   ```
3. **CocoaPods** (macOS/iOS Flutter plugins need it):
   ```bash
   sudo gem install cocoapods
   pod setup
   ```
4. Verify:
   ```bash
   flutter doctor
   ```
   → `[✓] Xcode - develop for iOS and macOS` (plus `[✓] CocoaPods`).

Once those are green, the macOS/iOS commands above are all that's left. Ask the assistant
to "build the macOS DMG and iOS app" and it will run them.
