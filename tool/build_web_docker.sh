#!/usr/bin/env bash
# Build the Peso-FinFlow web app inside Docker and export the static site to
# ./build/web. No web server is bundled — serve the output with your own nginx
# (reference config: deploy/nginx-finflow.conf.example).
#
# Usage:
#   ./tool/build_web_docker.sh          # release build
#   ./tool/build_web_docker.sh demo     # release build seeded with demo data
set -euo pipefail

cd "$(dirname "$0")/.."

DEMO="${1:-}"

if [ "$DEMO" = "demo" ]; then
  echo ">> docker build (FINFLOW_DEMO_DATA=true, pwa offline-first) …"
  docker build --build-arg FINFLOW_DEMO_DATA=true -o build/web .
else
  echo ">> docker build (release, pwa offline-first) …"
  docker build -o build/web .
fi

echo ">> exported ./build/web"
echo "   Serve it with your nginx, e.g. root $(pwd)/build/web;"
echo "   see deploy/nginx-finflow.conf.example for the required config."
