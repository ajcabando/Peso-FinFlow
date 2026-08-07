# syntax=docker/dockerfile:1
# Peso-FinFlow web — build-only image.
#
# Deliberately ships NO web server: the app is served by the host's own nginx.
# Build with:
#   docker build -o build/web .                          # release build
#   docker build --build-arg FINFLOW_DEMO_DATA=true -o build/web .   # seeded demo data
# then point nginx at the exported ./build/web (see deploy/nginx-finflow.conf.example).
#
# The Flutter SDK is pinned to the project's version (3.44.8 → Dart 3.12.2)
# and downloaded from Flutter's official release server — no reliance on
# third-party image rebuild freshness.

# ---- build stage: compile the Flutter web app ----
# Flutter publishes only x86_64 Linux SDKs — pin linux/amd64 so the binaries
# run under Docker's emulation on Apple Silicon (see docs/WEB_APP.md gotchas).
FROM --platform=linux/amd64 debian:bookworm-slim AS build

# System deps for the Flutter/Dart toolchain (web build only).
RUN apt-get update && apt-get install -y --no-install-recommends \
      curl git unzip xz-utils zip ca-certificates libstdc++6 \
    && rm -rf /var/lib/apt/lists/*

# Pinned Flutter SDK (override with --build-arg FLUTTER_VERSION=<tag>).
ARG FLUTTER_VERSION=3.44.8
ENV FLUTTER_ROOT=/opt/flutter
RUN curl -fsSL -o /tmp/flutter.tar.xz \
      https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz \
    && tar xf /tmp/flutter.tar.xz -C /opt \
    && rm /tmp/flutter.tar.xz \
    && git config --global --add safe.directory /opt/flutter \
    && git config --global --add safe.directory /opt/flutter/bin/cache/pkg/sky_engine \
    && /opt/flutter/bin/flutter --version
ENV PATH="$FLUTTER_ROOT/bin:$PATH"

WORKDIR /app

# Resolve dependencies first so rebuilds are cached.
COPY pubspec.yaml pubspec.lock ./
RUN flutter config --no-analytics && flutter pub get

COPY . .

ARG FINFLOW_DEMO_DATA=false
RUN if [ "$FINFLOW_DEMO_DATA" = "true" ]; then \
      flutter build web --release --pwa-strategy=offline-first --dart-define=FINFLOW_DEMO_DATA=true; \
    else \
      flutter build web --release --pwa-strategy=offline-first; \
    fi

# ---- artifact stage: the static site only (no server, no Flutter SDK) ----
FROM scratch AS artifact
COPY --from=build /app/build/web /
