#!/usr/bin/env bash
# Usage: ./scripts/deploy.sh <image-tag>     e.g. ./scripts/deploy.sh 2.0.0
set -euo pipefail
cd "$(dirname "$0")/.."

TAG="${1:?Usage: deploy.sh <image-tag>}"
HEALTH_URL="${HEALTH_URL:-http://localhost/health}"
TIMEOUT="${HEALTH_TIMEOUT:-60}"
STATE=".deploy"; mkdir -p "$STATE"

[ -f .env ] && [ -f app.env ] || { echo "ERROR: .env/app.env missing (copy the *.example files)"; exit 1; }

CURRENT="$(cat "$STATE/current_tag" 2>/dev/null || true)"
echo "==> Deploying tag '$TAG' (currently running: ${CURRENT:-none})"

# Save chosen tag into .env so later docker compose commands use it
if grep -q '^APP_TAG=' .env; then sed -i "s/^APP_TAG=.*/APP_TAG=$TAG/" .env
else echo "APP_TAG=$TAG" >> .env; fi

if ! docker compose up -d --pull missing; then
  echo "DEPLOY FAILED: could not start image tag '$TAG' (does it exist?)"
  exit 1
fi

echo "==> Waiting for $HEALTH_URL (max ${TIMEOUT}s)"
deadline=$((SECONDS + TIMEOUT))
until [ "$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 "$HEALTH_URL")" = "200" ]; do
  if [ "$SECONDS" -ge "$deadline" ]; then
    echo "DEPLOY FAILED: $HEALTH_URL did not return 200 within ${TIMEOUT}s"
    docker compose ps
    docker compose logs --tail=30 app
    [ -n "$CURRENT" ] && echo "Last good release: $CURRENT  ->  ./scripts/deploy.sh $CURRENT"
    exit 1
  fi
  sleep 2
done

if [ -n "$CURRENT" ] && [ "$CURRENT" != "$TAG" ]; then echo "$CURRENT" > "$STATE/previous_tag"; fi
echo "$TAG" > "$STATE/current_tag"
echo "$(date -u +%FT%TZ) deployed $TAG" >> "$STATE/history.log"

echo "==> DEPLOY OK"
echo "version : $(curl -s http://localhost/version)"
echo "response: $(curl -s http://localhost/)"
echo "image   : $(docker compose images app --format json | jq -r '.[0] | "\(.Repository):\(.Tag) \(.ID)"' 2>/dev/null || true)"
