#!/usr/bin/env bash
set -euo pipefail
TMPDIR=$(mktemp -d)
export HOME="$TMPDIR"
mkdir -p "$HOME/.kimi/credentials"
cat > "$HOME/.kimi/credentials/kimi-code.json" <<'JSON'
{"access_token":"a","refresh_token":"r","expires_at":9999999999}
JSON
OUT=$(bash scripts/get_kimi_usage.sh --check-credentials 2>&1)
if [[ -n "$OUT" ]]; then
  echo "unexpected output: $OUT"
  exit 1
fi
