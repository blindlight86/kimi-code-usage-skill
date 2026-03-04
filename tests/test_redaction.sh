#!/usr/bin/env bash
set -euo pipefail
OUT=$(ACCESS_TOKEN='eyJ-very-secret-token-value' REFRESH_TOKEN='refresh_token_super_secret' bash scripts/get_kimi_usage.sh --debug 2>&1 || true)
if ! echo "$OUT" | grep -q 'access_token='; then
  echo "missing debug auth output"
  exit 1
fi
if echo "$OUT" | grep -E 'eyJ|refresh_token_super_secret|very-secret-token' ; then
  echo "token leak"
  exit 1
fi
