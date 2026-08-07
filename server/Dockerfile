# finflow-api — multi-stage production image.
#
# Build:  docker build -t finflow-api ./server
# Run:    handled by docker-compose.yml (migrate + finflow-api services).

# ---- build stage -----------------------------------------------------------
FROM node:22-alpine AS build
WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci

COPY . .
RUN npm run build \
  # tsc emits only .ts files — copy the generated migration SQL next to the
  # compiled migrate script so `node dist/drizzle/migrate.js` can find it.
  && cp -r src/drizzle/migrations dist/drizzle/migrations

# ---- runtime stage ----------------------------------------------------------
FROM node:22-alpine AS runtime
ENV NODE_ENV=production
WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force

COPY --from=build /app/dist ./dist

# Run as an unprivileged user; the image never needs root.
USER node

EXPOSE 8080

HEALTHCHECK --interval=10s --timeout=3s --start-period=15s --retries=3 \
  CMD wget -q -O /dev/null http://127.0.0.1:8080/health || exit 1

CMD ["node", "dist/main.js"]
