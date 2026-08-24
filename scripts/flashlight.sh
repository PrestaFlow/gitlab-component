#!/usr/bin/env bash
# flashlight.sh — Start a PrestaShop Flashlight container so PrestaFlow tests
# have a working PrestaShop instance to hit. Mirrors src/flashlight/ from the
# GitHub Action (compose-template + docker + mount resolution).
set -euo pipefail

if [ "${PRESTAFLOW_FLASHLIGHT:-false}" != "true" ]; then
  echo "flashlight: disabled — skipping"
  exit 0
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "flashlight: docker CLI not available — set up docker:dind service (already declared by the component)"
  exit 1
fi

PS_VERSION="${PRESTAFLOW_PS_VERSION:-latest}"
MODE="${PRESTAFLOW_FLASHLIGHT_MOUNT:-auto}"
INIT_SCRIPTS="${PRESTAFLOW_FLASHLIGHT_INIT_SCRIPTS:-}"
WORKSPACE="${CI_PROJECT_DIR:-$PWD}"
WORKSPACE_BASENAME=$(basename "$WORKSPACE")

# --- mount resolution (mirrors src/flashlight/mount.ts) ---
COMPOSER_NAME=""
COMPOSER_TYPE=""
if [ -f "$WORKSPACE/composer.json" ]; then
  COMPOSER_NAME=$(jq -r '.name // ""' "$WORKSPACE/composer.json" 2>/dev/null || echo "")
  COMPOSER_TYPE=$(jq -r '.type // ""' "$WORKSPACE/composer.json" 2>/dev/null || echo "")
fi

# Prefer the short name (after the vendor slash) when composer.name is "vendor/name".
NAME="$WORKSPACE_BASENAME"
if [ -n "$COMPOSER_NAME" ]; then
  case "$COMPOSER_NAME" in
    */*) NAME="${COMPOSER_NAME##*/}" ;;
    *)   NAME="$COMPOSER_NAME" ;;
  esac
fi

case "$MODE" in
  root)
    CONTAINER_PATH="/var/www/html"
    ;;
  modules)
    CONTAINER_PATH="/var/www/html/modules/${NAME}"
    ;;
  themes)
    CONTAINER_PATH="/var/www/html/themes/${NAME}"
    ;;
  auto)
    case "$COMPOSER_TYPE" in
      prestashop-module) CONTAINER_PATH="/var/www/html/modules/${NAME}" ;;
      prestashop-theme)  CONTAINER_PATH="/var/www/html/themes/${NAME}" ;;
      *)
        CONTAINER_PATH="/var/www/html/modules/${WORKSPACE_BASENAME}"
        echo "flashlight: composer.json missing or type unknown — defaulting to $CONTAINER_PATH. Set flashlight_mount to override."
        ;;
    esac
    ;;
  *)
    echo "flashlight: invalid mount mode '$MODE' (expected auto|root|modules|themes)"
    exit 1
    ;;
esac

echo "flashlight: mounting $WORKSPACE at $CONTAINER_PATH (mode=$MODE, PS $PS_VERSION)"

# --- init scripts path validation ---
INIT_SCRIPTS_HOST=""
if [ -n "$INIT_SCRIPTS" ]; then
  case "$INIT_SCRIPTS" in
    /*) INIT_SCRIPTS_HOST="$INIT_SCRIPTS" ;;
    *)  INIT_SCRIPTS_HOST="$WORKSPACE/$INIT_SCRIPTS" ;;
  esac
  if [ ! -d "$INIT_SCRIPTS_HOST" ]; then
    echo "flashlight: flashlight_init_scripts path does not exist or is not a directory: $INIT_SCRIPTS_HOST"
    exit 1
  fi
  echo "flashlight: mounting init-scripts from $INIT_SCRIPTS_HOST → /tmp/init-scripts (ro)"
fi

# --- port pick (8000, 8001, 8002 in order) ---
PORT=""
for p in 8000 8001 8002; do
  if ! (echo >"/dev/tcp/127.0.0.1/$p") 2>/dev/null; then
    PORT="$p"; break
  fi
done
[ -z "$PORT" ] && { echo "flashlight: no free port among 8000..8002"; exit 1; }

# --- compose file (matches src/flashlight/compose-template.ts) ---
COMPOSE_DIR="$WORKSPACE/.prestaflow-flashlight"
mkdir -p "$COMPOSE_DIR"
COMPOSE_FILE="$COMPOSE_DIR/compose.yml"

EXTRA_VOLUME=""
if [ -n "$INIT_SCRIPTS_HOST" ]; then
  EXTRA_VOLUME="      - ${INIT_SCRIPTS_HOST}:/tmp/init-scripts:ro"
fi

cat >"$COMPOSE_FILE" <<YAML
services:
  prestashop:
    image: prestashop/prestashop-flashlight:${PS_VERSION}
    depends_on:
      mysql:
        condition: service_healthy
    ports:
      - "${PORT}:80"
    volumes:
      - ${WORKSPACE}:${CONTAINER_PATH}
${EXTRA_VOLUME}
    environment:
      PS_DOMAIN: localhost:${PORT}
      DEBUG_MODE: 0
      INIT_ON_RESTART: 0

  mysql:
    image: mariadb:lts
    healthcheck:
      test: ["CMD", "healthcheck.sh", "--connect"]
      interval: 10s
      timeout: 10s
      retries: 5
    environment:
      MYSQL_USER: prestashop
      MYSQL_PASSWORD: prestashop
      MYSQL_ROOT_PASSWORD: prestashop
      MYSQL_DATABASE: prestashop
YAML

echo "flashlight: starting stack via docker compose"
docker compose -f "$COMPOSE_FILE" up -d

# --- wait for HTTP 200-399 on http://localhost:$PORT (up to 4 min) ---
URL="http://localhost:${PORT}"
DEADLINE=$(( $(date +%s) + 240 ))
while [ "$(date +%s)" -lt "$DEADLINE" ]; do
  CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 "$URL" || echo "000")
  if [ "$CODE" -ge 200 ] 2>/dev/null && [ "$CODE" -lt 400 ] 2>/dev/null; then
    echo "flashlight: ready at $URL (HTTP $CODE)"
    break
  fi
  sleep 2
done

if [ "$(date +%s)" -ge "$DEADLINE" ]; then
  echo "flashlight: not ready after 240s at $URL — dumping logs"
  docker compose -f "$COMPOSE_FILE" logs || true
  exit 1
fi

# --- expose to later steps ---
# The PHP library reads .env / .env.local (phpdotenv), not process env, so we
# write both channels — matches src/main.ts's writeDotEnvLocal.
export PRESTAFLOW_FO_URL="${URL}/"
{
  echo "PRESTAFLOW_FO_URL=${URL}/"
  echo "PRESTAFLOW_PS_VERSION=${PS_VERSION}"
} > "$WORKSPACE/.env.local"

# Keep them around for the outputs.sh dotenv report too.
{
  echo "PRESTAFLOW_FO_URL=${URL}/"
  echo "PRESTAFLOW_PS_VERSION=${PS_VERSION}"
} >> prestaflow.env

echo "flashlight: ready — PRESTAFLOW_FO_URL=${URL}/"
