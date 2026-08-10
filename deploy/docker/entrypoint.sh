#!/bin/sh
# Peso-FinFlow web image entrypoint — renders the nginx config template
# with the WEB_PORT / SITE_PORT environment variables, then starts nginx.
#
# The `00-` prefix makes this run BEFORE the base image's
# `20-envsubst-on-templates.sh` hook. That hook renders every *.template
# under /etc/nginx/templates into /etc/nginx/conf.d — if it processed our
# full-nginx.conf template, it would leave a stray conf.d/nginx.conf that
# could collide with the main config on base images that `include conf.d`.
# So we render to /etc/nginx/nginx.conf first, then delete the template so
# the envsubst hook has nothing left to render.

set -eu

: "${WEB_PORT:=8372}"
: "${SITE_PORT:=8373}"

TEMPLATE=/etc/nginx/templates/nginx.conf.template
TARGET=/etc/nginx/nginx.conf

if [ -f "$TEMPLATE" ]; then
  sed \
    -e "s/__WEB_PORT__/$WEB_PORT/g" \
    -e "s/__SITE_PORT__/$SITE_PORT/g" \
    "$TEMPLATE" > "$TARGET"
  echo "finflow-web: rendered nginx.conf (web=$WEB_PORT, site=$SITE_PORT)"

  # Don't let the base image's envsubst hook render the template again.
  rm -f "$TEMPLATE"
  # Belt-and-braces: drop any leftover envsubst output from a stale image.
  rm -f /etc/nginx/conf.d/nginx.conf
else
  echo "finflow-web: template not found — starting nginx with existing config" >&2
fi

exit 0
