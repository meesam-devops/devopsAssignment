#!/usr/bin/env bash
# Starts an image, checks all endpoints, fails if anything is wrong.
set -euo pipefail
IMAGE="${1:?Usage: smoke-test.sh <image>}"
NAME="smoke-$$"

docker run -d --name "$NAME" -p 18080:8080 \
  -e APP_VERSION=smoke -e APP_MESSAGE="smoke test" "$IMAGE" >/dev/null
trap 'docker logs "$NAME" 2>&1 | tail -20; docker rm -f "$NAME" >/dev/null' EXIT

for i in $(seq 1 30); do
  curl -fs http://localhost:18080/health >/dev/null && break
  sleep 1
done

curl -fsS http://localhost:18080/health  | grep -q Healthy
curl -fsS http://localhost:18080/version | grep -q '"smoke"'
curl -fsS http://localhost:18080/        | grep -q 'smoke test'
[ "$(docker exec "$NAME" id -u)" != "0" ] || { echo "Running as root!"; exit 1; }
echo "SMOKE TEST PASSED for $IMAGE"
