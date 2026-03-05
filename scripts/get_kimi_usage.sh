#!/usr/bin/env bash
set -euo pipefail

CRED_FILE="${HOME}/.kimi/credentials/kimi-code.json"
API_BASE="${KIMI_USAGE_API_BASE:-https://www.kimi.com/api}"
API_V2_BASE="${KIMI_USAGE_API_V2_BASE:-https://www.kimi.com/apiv2}"
DEBUG=0

redact() {
  local s="$1"
  local n=${#s}
  if (( n == 0 )); then
    echo ""
  elif (( n <= 10 )); then
    echo "***"
  else
    echo "****...${s:n-4:4}"
  fi
}

load_token_from_file() {
  local key="$1"
  if [[ -f "$CRED_FILE" ]]; then
    python3 - "$CRED_FILE" "$key" <<'PY'
import json
import sys
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    data = json.load(f)
print(data.get(sys.argv[2], ''))
PY
    return 0
  fi
  printf '\n'
}

load_access_token() {
  if [[ -n "${ACCESS_TOKEN:-}" ]]; then
    printf '%s\n' "$ACCESS_TOKEN"
    return 0
  fi
  load_token_from_file "access_token"
}

load_refresh_token() {
  if [[ -n "${REFRESH_TOKEN:-}" ]]; then
    printf '%s\n' "$REFRESH_TOKEN"
    return 0
  fi
  load_token_from_file "refresh_token"
}

decode_access_claims() {
  local token="$1"
  python3 - "$token" <<'PY'
import base64
import json
import sys

token = sys.argv[1]
parts = token.split(".")
if len(parts) < 2:
    print("")
    print("")
    raise SystemExit(0)

segment = parts[1]
segment += "=" * ((4 - len(segment) % 4) % 4)
try:
    payload = json.loads(base64.urlsafe_b64decode(segment.encode("utf-8")).decode("utf-8"))
except Exception:
    print("")
    print("")
    print("")
    print("")
    raise SystemExit(0)

print(payload.get("ssid", ""))
print(payload.get("device_id", ""))
print(payload.get("sub", ""))
membership = payload.get("membership")
if isinstance(membership, dict):
    print(membership.get("level", ""))
else:
    print("")
PY
}

api_request_usage() {
  local token="$1"
  local ssid="$2"
  local device_id="$3"
  local user_id="$4"

  # Real Kimi Code billing endpoint for usage in code console.
  if curl -fsS \
    -X POST \
    -H "Authorization: Bearer ${token}" \
    -H "Accept: */*" \
    -H "connect-protocol-version: 1" \
    -H "Content-Type: application/json" \
    -H "r-timezone: Asia/Shanghai" \
    -H "x-language: zh-CN" \
    -H "x-msh-platform: web" \
    -H "x-msh-version: 1.0.0" \
    ${ssid:+-H "x-msh-session-id: ${ssid}"} \
    ${device_id:+-H "x-msh-device-id: ${device_id}"} \
    ${user_id:+-H "x-traffic-id: ${user_id}"} \
    -d '{"scope":["FEATURE_CODING"]}' \
    "${API_V2_BASE}/kimi.gateway.billing.v1.BillingService/GetUsages"; then
    return 0
  fi

  # Compatibility fallback.
  if curl -fsS \
    -X POST \
    -H "Authorization: Bearer ${token}" \
    -H "Accept: application/json, text/plain, */*" \
    -H "Content-Type: application/json" \
    -H "r-timezone: Asia/Shanghai" \
    -H "x-language: zh-CN" \
    -H "x-msh-platform: web" \
    -H "x-msh-version: 1.0.0" \
    ${ssid:+-H "x-msh-session-id: ${ssid}"} \
    ${device_id:+-H "x-msh-device-id: ${device_id}"} \
    ${device_id:+-H "x-traffic-id: ${device_id}"} \
    -d '{}' \
    "${API_BASE}/user/usage"; then
    return 0
  fi

  # Backward compatibility for older/mock plan endpoints.
  curl -fsS \
    -H "Authorization: Bearer ${token}" \
    -H "Accept: application/json" \
    "${API_BASE}/usages"
}

normalize_api_json() {
  local payload="$1"
  local membership_claim="${2:-}"
  python3 - "$payload" "$membership_claim" <<'PY'
import json
import sys
from scripts.parse_usage import normalize_api_payload

result = normalize_api_payload(sys.argv[1])
membership_claim = sys.argv[2]
if result.get("membership") is None and membership_claim:
    result["membership"] = str(membership_claim)
    if result.get("membershipName") is None:
        result["membershipName"] = "Moderato" if str(membership_claim) == "20" else str(membership_claim)
print(json.dumps(result, ensure_ascii=False))
PY
}

normalize_browser_text() {
  local payload="$1"
  python3 - "$payload" <<'PY'
import json
import sys
from scripts.parse_usage import normalize_browser_text

print(json.dumps(normalize_browser_text(sys.argv[1]), ensure_ascii=False))
PY
}

if [[ "${1:-}" == "--debug" ]]; then
  DEBUG=1
  shift || true
fi

if [[ "$DEBUG" == "1" ]]; then
  ACCESS_TOKEN_VAL="$(load_access_token)"
  REFRESH_TOKEN_VAL="$(load_refresh_token)"
  echo "access_token=$(redact "$ACCESS_TOKEN_VAL")" >&2
  echo "refresh_token=$(redact "$REFRESH_TOKEN_VAL")" >&2
fi

if [[ "${KIMI_USAGE_FORCE_BROWSER:-0}" == "1" ]]; then
  bash scripts/bootstrap_kimi_login.sh
  echo "$(normalize_browser_text "Membership: UNKNOWN")"
  exit 0
fi

if [[ "${1:-}" == "--check-credentials" ]]; then
  test -f "$CRED_FILE"
  exit 0
fi

if [[ "${1:-}" == "--api-only" ]]; then
  ACCESS_TOKEN_VAL="$(load_access_token)"
  CLAIMS_TEXT="$(decode_access_claims "$ACCESS_TOKEN_VAL")"
  SSID="$(printf '%s\n' "$CLAIMS_TEXT" | sed -n '1p')"
  DEVICE_ID="$(printf '%s\n' "$CLAIMS_TEXT" | sed -n '2p')"
  USER_ID="$(printf '%s\n' "$CLAIMS_TEXT" | sed -n '3p')"
  api_request_usage "$ACCESS_TOKEN_VAL" "$SSID" "$DEVICE_ID" "$USER_ID"
  exit 0
fi

if [[ -f "$CRED_FILE" || -n "${ACCESS_TOKEN:-}" ]]; then
  API_CMD=("$0" --api-only)
  if [[ "$DEBUG" == "1" ]]; then
    API_CMD=("$0" --debug --api-only)
  fi
  ACCESS_TOKEN_VAL="$(load_access_token)"
  CLAIMS_TEXT="$(decode_access_claims "$ACCESS_TOKEN_VAL")"
  MEMBERSHIP_CLAIM="$(printf '%s\n' "$CLAIMS_TEXT" | sed -n '4p')"
  if API_PAYLOAD="$("${API_CMD[@]}" 2>/dev/null)"; then
    normalize_api_json "$API_PAYLOAD" "$MEMBERSHIP_CLAIM"
    exit 0
  elif [[ -n "${ACCESS_TOKEN:-}" || "${KIMI_USAGE_NO_BROWSER_FALLBACK:-0}" == "1" ]]; then
    # If caller explicitly passed token, avoid forcing browser fallback.
    exit 1
  fi
fi

bash scripts/bootstrap_kimi_login.sh >/dev/null 2>&1 || true
echo "$(normalize_browser_text "Membership: UNKNOWN")"
