# syntax=docker/dockerfile:1
# Peso-FinFlow — single deployable image: web app + marketing website.
#
# Two build modes:
#
#   1) Build-only export (unchanged legacy behaviour):
#        docker build --target artifact -o build/web .
#      Exports the static Flutter web build to ./build/web — serve it with
#      your own nginx (deploy/nginx-finflow.conf.example). No server shipped.
#
#   2) Full runtime image (web app :8372 + marketing site :8373 in nginx):
#        docker build -t finflow-web .
#        docker run -p 8372:8372 -p 8373:8373 -e WEB_PORT=8372 -e SITE_PORT=8373 finflow-web
#      Ports are runtime-configurable via WEB_PORT / SITE_PORT env vars
#      (defaults 8372 / 8373) — map them however you like on your server.
#      See docker-compose.web.yml for the compose flavour.
#
# Build args:
#   FINFLOW_API_URL  — API base URL compiled into the web app for sync.
#                      Defaults to http://127.0.0.1:8080 (local stack).
#                      For a server: http://<host>:8080 or https://api.…
#   FINFLOW_DEMO_DATA — 'true' seeds demo data on first launch (screenshots).
#   FLUTTER_VERSION  — pinned Flutter SDK tag (default 3.44.8).

# ---- build stage: compile the Flutter web app ----
# Flutter publishes only x86_64 Linux SDKs — pin linux/amd64 so the binaries
# run under Docker's emulation on Apple Silicon (see docs/WEB_APP.md gotchas).
FROM --platform=linux/amd64 debian:bookworm-slim AS build

RUN apt-get update && apt-get install -y --no-install-recommends \
      curl git unzip xz-utils zip ca-certificates libstdc++6 \
    && rm -rf /var/lib/apt/lists/*

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

COPY pubspec.yaml pubspec.lock ./
RUN flutter config --no-analytics && flutter pub get

COPY . .

ARG FINFLOW_DEMO_DATA=false
ARG FINFLOW_API_URL=http://127.0.0.1:8080
RUN if [ "$FINFLOW_DEMO_DATA" = "true" ]; then \
      flutter build web --release --pwa-strategy=offline-first \
        --dart-define=FINFLOW_DEMO_DATA=true \
        --dart-define=FINFLOW_API_URL=$FINFLOW_API_URL; \
    else \
      flutter build web --release --pwa-strategy=offline-first \
        --dart-define=FINFLOW_API_URL=$FINFLOW_API_URL; \
    fi

# ---- artifact stage: the static app only (no server, no Flutter SDK) ----
FROM scratch AS artifact
COPY --from=build /app/build/web /

# ---- runtime stage: nginx serving the app AND the marketing site ----
FROM nginx:1.27-alpine AS runtime

# nginx defaults to logging to stdout/stderr on alpine — keep it that way
# for `docker logs`.
ENV WEB_PORT=8372 \
    SITE_PORT=8373

COPY --from=build /app/build/web /usr/share/nginx/html/app
COPY website /usr/share/nginx/html/site

# Runtime port templating: the config template is rendered by entrypoint.sh
# (runs FIRST via the 00- prefix, before the base image's envsubst hook)
# from the WEB_PORT / SITE_PORT env vars so one image deploys anywhere.
COPY deploy/docker/nginx-finflow.conf.template /etc/nginx/templates/nginx.conf.template
COPY deploy/docker/entrypoint.sh /docker-entrypoint.d/00-finflow-ports.sh
RUN chmod +x /docker-entrypoint.d/00-finflow-ports.sh

EXPOSE 8372 8373
