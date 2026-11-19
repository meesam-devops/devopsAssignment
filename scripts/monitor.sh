#!/usr/bin/env bash
# Exit 0 = healthy, 1 = unhealthy.  Use --loop to keep watching.
URL="${HEALTH_URL:-http://localhost/health}"
INTERVAL="${INTERVAL:-10}"

check() {
  local code ts
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$URL")
  ts=$(date -u +%FT%TZ)
  if [ "$code" = "200" ]; then
    echo "$ts OK    $URL -> HTTP $code"; return 0
  else
    echo "$ts ALERT $URL -> HTTP $code (application unavailable)" >&2
    logger -t app-monitor "ALERT $URL HTTP $code" 2>/dev/null || true
    return 1
  fi
}

if [ "${1:-}" = "--loop" ]; then
  while true; do check || true; sleep "$INTERVAL"; done
else
  check
fi
