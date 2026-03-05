#!/usr/bin/env bash
set -euo pipefail

CRED_DIR="${HOME}/.kimi/credentials"
CRED_FILE="${CRED_DIR}/kimi-code.json"
LOGIN_BASE="${KIMI_LOGIN_API_BASE:-https://www.kimi.com/api/user/wx/register_login}"
QR_TIMEOUT_SEC="${KIMI_QR_LOGIN_TIMEOUT_SEC:-180}"
POLL_INTERVAL_SEC="${KIMI_QR_POLL_INTERVAL_SEC:-2}"

persist_credentials() {
  local json_payload="$1"
  mkdir -p "$CRED_DIR"
  umask 077
  printf '%s\n' "$json_payload" > "$CRED_FILE"
  chmod 600 "$CRED_FILE"
}

poll_qr_once() {
  local login_id="$1"
  local ts
  ts="$(python3 - <<'PY'
import time
print(int(time.time() * 1000))
PY
)"
  curl -fsS \
    -H "accept: application/json, text/plain, */*" \
    -H "x-language: zh-CN" \
    -H "x-msh-platform: web" \
    -H "r-timezone: Asia/Shanghai" \
    "${LOGIN_BASE}/${login_id}?t=${ts}"
}

if [[ "${1:-}" == "--write-sample" ]]; then
  persist_credentials '{"access_token":"sample","refresh_token":"sample","expires_at":0}'
  exit 0
fi

if [[ "${1:-}" == "--prepare-qr" ]]; then
  if [[ -n "${KIMI_BOOTSTRAP_MARKER:-}" ]]; then
    mkdir -p "$(dirname "${KIMI_BOOTSTRAP_MARKER}")"
    printf 'ok\n' > "${KIMI_BOOTSTRAP_MARKER}"
    echo '{"success":true,"marker_mode":true,"qr_expires_in_seconds":180}'
    exit 0
  fi

  node scripts/browser/wx-register-login.mjs
  exit 0
fi

if [[ "${1:-}" == "--poll-qr" ]]; then
  login_id="${2:-}"
  if [[ -z "$login_id" ]]; then
    echo '{"success":false,"error":"missing login_id"}'
    exit 2
  fi
  poll_qr_once "$login_id"
  exit 0
fi

if [[ "${1:-}" == "--refresh" ]]; then
  if [[ -n "${KIMI_BOOTSTRAP_MARKER:-}" ]]; then
    mkdir -p "$(dirname "${KIMI_BOOTSTRAP_MARKER}")"
    printf 'ok\n' > "${KIMI_BOOTSTRAP_MARKER}"
    echo '{"success":true,"marker_mode":true}'
    exit 0
  fi

  QR_JSON="$(bash scripts/refresh_kimi_token.sh --prepare-qr)"
  login_id="$(python3 - <<'PY' "$QR_JSON"
import json,sys
d=json.loads(sys.argv[1])
print(d.get("login_id",""))
PY
)"
  qr_screenshot="$(python3 - <<'PY' "$QR_JSON"
import json,sys
d=json.loads(sys.argv[1])
print(d.get("qr_screenshot",""))
PY
)"
  qr_expires="$(python3 - <<'PY' "$QR_JSON" "$QR_TIMEOUT_SEC"
import json,sys
d=json.loads(sys.argv[1])
fallback=int(sys.argv[2])
print(d.get("qr_expires_in_seconds", fallback))
PY
)"

  if [[ -z "$login_id" ]]; then
    echo "$QR_JSON"
    exit 1
  fi

  echo "QR ready: ${qr_screenshot}" >&2
  echo "请将二维码发送到发问会话，剩余 ${qr_expires} 秒可扫码。" >&2

  START_TS="$(python3 - <<'PY'
import time
print(int(time.time()))
PY
)"
  LAST_NOTICE_TS="$START_TS"

  while true; do
    NOW_TS="$(python3 - <<'PY'
import time
print(int(time.time()))
PY
)"
    ELAPSED=$((NOW_TS - START_TS))
    REMAIN=$((qr_expires - ELAPSED))
    if (( REMAIN <= 0 )); then
      echo "{\"success\":false,\"reason\":\"timeout waiting for QR scan\",\"login_id\":\"${login_id}\",\"qr_screenshot\":\"${qr_screenshot}\",\"remaining_seconds\":0}" 
      exit 1
    fi

    POLL_JSON="$(bash scripts/refresh_kimi_token.sh --poll-qr "$login_id")"
    if python3 - "$POLL_JSON" "$CRED_FILE" "$qr_screenshot" "$REMAIN" "$login_id" <<'PY'
import json
import os
import stat
import sys
import time

raw = json.loads(sys.argv[1])
cred_file = sys.argv[2]
qr_screenshot = sys.argv[3]
remaining = int(sys.argv[4])
login_id = sys.argv[5]

status = raw.get("status")
if status != "login":
    print(json.dumps({
        "success": False,
        "status": status or "pending",
        "login_id": login_id,
        "qr_screenshot": qr_screenshot,
        "remaining_seconds": remaining,
    }, ensure_ascii=False))
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
    "qr_screenshot": qr_screenshot,
    "remaining_seconds": remaining,
    "access_token": redact(access),
    "refresh_token": redact(refresh),
}, ensure_ascii=False))
PY
    then
      exit 0
    fi

    if (( NOW_TS - LAST_NOTICE_TS >= 15 )); then
      echo "扫码等待中，剩余 ${REMAIN} 秒。" >&2
      LAST_NOTICE_TS="$NOW_TS"
    fi
    sleep "$POLL_INTERVAL_SEC"
  done
fi

cat <<'EOF' >&2
Usage:
  bash scripts/refresh_kimi_token.sh --prepare-qr
  bash scripts/refresh_kimi_token.sh --poll-qr <login_id>
  bash scripts/refresh_kimi_token.sh --refresh
  bash scripts/refresh_kimi_token.sh --write-sample
EOF
exit 2
