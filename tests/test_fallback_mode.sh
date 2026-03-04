#!/usr/bin/env bash
set -euo pipefail
TMPDIR=$(mktemp -d)
export HOME="$TMPDIR"
MARKER="$TMPDIR/bootstrap-called"
rm -f "$HOME/.kimi/credentials/kimi-code.json"
KIMI_BOOTSTRAP_MARKER="$MARKER" KIMI_USAGE_FORCE_BROWSER=1 bash scripts/get_kimi_usage.sh >/dev/null 2>&1 || true
if [[ ! -f "$MARKER" ]]; then
  echo "browser bootstrap was not invoked"
  exit 1
fi
