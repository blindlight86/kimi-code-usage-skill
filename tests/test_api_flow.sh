#!/usr/bin/env bash
set -euo pipefail
MOCK_DIR=$(mktemp -d)
cat > "$MOCK_DIR/usages" <<'JSON'
{"usage":{"limit":"100"}}
JSON
MOCK_PORT=18888
python3 -m http.server "$MOCK_PORT" --directory "$MOCK_DIR" >/dev/null 2>&1 &
PID=$!
trap 'kill $PID' EXIT
sleep 0.2
OUT=$(ACCESS_TOKEN=dummy KIMI_USAGE_API_BASE="http://127.0.0.1:${MOCK_PORT}" bash scripts/get_kimi_usage.sh --api-only 2>&1 || true)
if ! echo "$OUT" | grep -q '"usage"'; then
  echo "api output missing usage payload"
  exit 1
fi
