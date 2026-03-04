#!/usr/bin/env bash
set -euo pipefail

CRED_DIR="${HOME}/.kimi/credentials"
CRED_FILE="${CRED_DIR}/kimi-code.json"

persist_credentials() {
  local json_payload="$1"
  mkdir -p "$CRED_DIR"
  umask 077
  printf '%s\n' "$json_payload" > "$CRED_FILE"
  chmod 600 "$CRED_FILE"
}

if [[ "${1:-}" == "--write-sample" ]]; then
  persist_credentials '{"access_token":"sample","refresh_token":"sample","expires_at":0}'
  exit 0
fi

if [[ "${1:-}" == "--refresh" ]]; then
  if [[ -n "${KIMI_BOOTSTRAP_MARKER:-}" ]]; then
    mkdir -p "$(dirname "${KIMI_BOOTSTRAP_MARKER}")"
    printf 'ok\n' > "${KIMI_BOOTSTRAP_MARKER}"
    echo '{"success":true,"marker_mode":true}'
    exit 0
  fi

  QR_JSON="$(node scripts/browser/wx-register-login.mjs)"
  python3 - "$QR_JSON" "$CRED_FILE" <<'PY'
import json
import os
import stat
import sys
import time

raw = json.loads(sys.argv[1])
cred_file = sys.argv[2]

if not raw.get("success"):
    print(json.dumps(raw, ensure_ascii=False))
    sys.exit(1)

access = raw.get("access_token", "")
refresh = raw.get("refresh_token", "")
if not access or not refresh:
    print(json.dumps({"success": False, "error": "missing token fields"}, ensure_ascii=False))
    sys.exit(1)

payload = {
    "access_token": access,
    "refresh_token": refresh,
    "expires_at": int(time.time()) + 3600,
}

os.makedirs(os.path.dirname(cred_file), exist_ok=True)
with open(cred_file, "w", encoding="utf-8") as f:
    json.dump(payload, f, ensure_ascii=False, indent=2)
os.chmod(cred_file, 0o600)

def redact(s: str) -> str:
    if not s:
        return ""
    if len(s) <= 10:
        return "***"
    return "****..." + s[-4:]

print(json.dumps({
    "success": True,
    "saved": cred_file,
    "mode": oct(stat.S_IMODE(os.stat(cred_file).st_mode)),
    "qr_screenshot": raw.get("qr_screenshot", ""),
    "access_token": redact(access),
    "refresh_token": redact(refresh),
}, ensure_ascii=False))
PY
  exit 0
fi

cat <<'EOF' >&2
Usage:
  bash scripts/refresh_kimi_token.sh --refresh
  bash scripts/refresh_kimi_token.sh --write-sample
EOF
exit 2
