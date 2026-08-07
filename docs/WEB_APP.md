# Peso-FinFlow — Web App Plan (revised 2026-08-06)

**Decisions:** Docker **builds only** (no nginx bundled — the host's existing nginx serves the app) · web app is **installable as an app** from iOS Safari ("Add to Home Screen") and Android Chrome (PWA install prompt) · branding polish included.

## 1. Goal & reality check

Goal: a web app version of FinFlow with **the same UI and functionality**, built inside **Docker**, served by the user's own nginx, and **installable as an app** from mobile browsers.

Reality: the web version **already exists in this codebase** — Flutter compiles the exact same UI for web. The work is: branding polish on the web shell, PWA installability, a Docker build that produces the static site, and a test pass in the browser.

## 2. What already works on web (don't rebuild)

- `web/sqlite3.wasm` (734 KB) + `web/drift_worker.js` (355 KB) are committed — Drift's SQLite-WASM backend.
- `lib/database/database_connection.dart` conditionally opens `WasmDatabase` on web (relative URIs); native uses `drift_flutter`.
- Web release build compiles; `web/*` is copied into `build/web` automatically.
- Serving requirements (from `tool/serve_web.py`): **`.wasm → application/wasm`** MIME (nginx's default mime.types lacks it) and **SPA fallback** (`try_files … /index.html`) for go_router deep links.
- Testing hooks: `--dart-define=FINFLOW_DEMO_DATA=true` seeds demo data; `FINFLOW_SCREEN` auto-navigates.

## 3. Phase 1 — Branding + PWA shell (DONE)

- `web/index.html`: title **Peso-FinFlow**, description, `theme-color #6D5DF6`, iOS meta (`apple-mobile-web-app-capable`, status-bar style, app title) + `apple-touch-icon`.
- `web/manifest.json`: name **Peso-FinFlow**, `short_name` FinFlow, `display: standalone`, brand colors, real description, 192/512 + maskable icons.
- `web/icons/` regenerated from `dist/finflow_icon_1024.png` via **`tool/generate_web_icons.py`** (new): `Icon-192/512`, `Icon-maskable-192/512`, `apple-touch-icon.png` (180px RGB).
- **Installability**:
  - Android Chrome → install prompt: manifest + icons + service worker. Built with **`--pwa-strategy=offline-first`** (Flutter generates `flutter_service_worker.js` with a fetch handler + auto-registration). Also gives offline support.
  - iOS Safari → "Add to Home Screen": manifest + `apple-touch-icon` + `apple-mobile-web-app-capable` (all in place).

## 4. Phase 2 — Docker (build-only, nginx-free) — DONE

Files added:
- **`Dockerfile`** — multi-stage, **no web server bundled**:
  1. `debian:bookworm-slim` (pinned `linux/amd64` — Flutter publishes only x86_64 Linux SDKs; runs under Docker's emulation on Apple Silicon) with the **Flutter 3.44.8 SDK downloaded from Flutter's official release server** (pinned, reproducible — third-party images like `cirruslabs` are stale and fail the `sdk: ^3.12.2` constraint) → `flutter pub get` → `flutter build web --release --pwa-strategy=offline-first` (optionally `--dart-define=FINFLOW_DEMO_DATA=true` via `FINFLOW_DEMO_DATA` build arg).
  2. `scratch` artifact stage containing the static site (`build/web`).

Build + export (verified): `docker build -o build/web .` → 48 MB site in `./build/web` with `index.html`, `sqlite3.wasm`, `drift_worker.js`, `main.dart.js`, `flutter_service_worker.js`.
- **`.dockerignore`** — excludes `.git`, `build/`, `.dart_tool/`, `dist/` (26 MB IPAs), platform dirs, `tool/`, `test/`, docs.
- **`tool/build_web_docker.sh`** — `docker build -o build/web .` (exports the files to the host), or `./tool/build_web_docker.sh demo` for a seeded build.
- **`deploy/nginx-finflow.conf.example`** — reference server block for **your existing nginx**: `application/wasm` MIME (scoped location), immutable caching for `/assets/` + `.wasm`, no-cache for `flutter_service_worker.js`, SPA fallback.

Workflow:
```bash
./tool/build_web_docker.sh          # or: docker build -o build/web .
# point nginx root at ./build/web (adjust deploy/nginx-finflow.conf.example)
```

## 5. Phase 3 — Test (Docker, verified 2026-08-06)

**On this Mac (Docker Desktop):**

```bash
docker build -t finflow-web:local .          # 65MB artifact image, ~1 min (cached)
# serve the exported build through a throwaway nginx harness (test only — the
# build itself has no server; this mirrors deploy/nginx-finflow.conf.example):
docker run -d --name finflow-test -p 8092:80 \
  -v "$PWD/deploy/nginx-finflow.conf.example:/etc/nginx/conf.d/default.conf:ro" \
  -v "$PWD/build/web:/var/www/finflow:ro" nginx:alpine
```

Results (all pass):
1. Artifact image contains the full site (`sqlite3.wasm`, `drift_worker.js`, `flutter_service_worker.js`, `main.dart.js`, icons…).
2. `nginx -t` on the example conf: OK.
3. HTTP checks: `/` 200 · `/sqlite3.wasm` 200 with **`Content-Type: application/wasm`** + `no-cache` · deep link `/analytics` 200 (SPA fallback) · `/flutter_service_worker.js` 200 no-cache · `/manifest.json` 200 · `/assets/*` `max-age=31536000, immutable`.
4. Headless Chrome renders the app through the container: **dark-theme UI** (`#0F1117` bg + brand-purple accents) — same histogram as the known-good build.
5. Gotcha: the example conf declares `root /var/www/finflow;` — the harness must mount `build/web` at **that** path (mounting it at `/usr/share/nginx/html` gives 500s, because `try_files` finds nothing).

Still manual (needs a real browser): all tabs + **add a transaction → reload → persists** (OPFS), DevTools → Application → Service Workers (`flutter_service_worker.js` registered), and the mobile install prompts (Android Chrome / iOS Safari).

## 6. Phase 4 — Follow-ups (out of scope)

- CI: build + publish the artifact (GHCR or Pages) on push; repo is public.
- Deployment on a real host/VPS with the host nginx + HTTPS (Let's Encrypt).

## 7. Validation

- `flutter analyze` clean · `flutter test` (180) unaffected · `flutter build web --release --pwa-strategy=offline-first` compiles (with `flutter_service_worker.js` generated).
- `docker build -o build/web .` exports a working site.
- Browser smoke test (Section 5).

## 8. Risks & gotchas

- **No COOP/COEP**: `serve_web.py` deliberately omits them and the app works — keep them off unless persistence misbehaves.
- **Browser support**: SQLite WASM + OPFS solid in Chrome/Edge; Safari partial — test in Chrome.
- **Apple Silicon + Docker**: Flutter publishes only x86_64 Linux SDKs — the build stage MUST be `--platform=linux/amd64` (whole container runs under Docker's Rosetta emulation; without it the x86_64 dart binary crashes with `rosetta error: failed to open elf`).
- **`localhost` vs `127.0.0.1`**: `serve_web.py` binds IPv4 only; Chrome resolves `localhost` to `::1` first and shows a connection-error page. Use `http://127.0.0.1:8080` for headless/local checks (or bind `0.0.0.0`).
- **Third-party Flutter images are stale**: `cirruslabs/flutter:stable`/`:3.44.0` bundle Dart 3.12.0 < the project's `^3.12.2` — that's why the Dockerfile downloads the pinned official SDK instead.
- **Image/build**: first `docker build` downloads the Flutter SDK (~1 GB, slow; cached after).
- **Biometrics**: `local_auth` is native-only — PIN lock works on web; verify no crash in the browser pass.
- **iOS install**: needs the site served over HTTPS (or localhost) for a clean standalone experience.
- **Manifest `scope: "/"`** assumes root serving; if the site is ever deployed under a subpath, rebuild with `--base-href=/finflow/` and set the manifest `scope`/`start_url` to match, or installability breaks.
