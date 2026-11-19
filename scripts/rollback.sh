#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
PREV="$(cat .deploy/previous_tag 2>/dev/null || true)"
[ -n "$PREV" ] || { echo "ERROR: no previous release recorded"; exit 1; }
echo "==> ROLLBACK: $(cat .deploy/current_tag) -> $PREV"
exec ./scripts/deploy.sh "$PREV"
