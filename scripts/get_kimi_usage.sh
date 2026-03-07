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
from datetime import datetime, timezone

def _membership_name(level):
    if level is None:
        return None
    if str(level) == "20":
        return "Moderato"
    return str(level)

def _safe_int(value):
    try:
        return int(str(value))
    except Exception:
        return None

def _percent(used, limit):
    if used is None or limit in (None, 0):
        return None
    return round((used / limit) * 100, 2)

def _ratio(used, limit):
    if used is None or limit in (None, 0):
        return None
    return round(used / limit, 4)

def _percent_text(used, limit):
    pct = _percent(used, limit)
    if pct is None:
        return None
    return f"{pct}%"

def _hours_to_reset(reset_time):
    if not reset_time:
        return None
    try:
        ts = datetime.fromisoformat(str(reset_time).replace("Z", "+00:00"))
        delta = ts - datetime.now(timezone.utc)
        hours = delta.total_seconds() / 3600
        return max(round(hours, 2), 0.0)
    except Exception:
        return None

def normalize_api_payload(payload_text):
    payload = json.loads(payload_text)
    usages = payload.get("usages")
    if isinstance(usages, list) and usages:
        coding = None
        for item in usages:
            if isinstance(item, dict) and item.get("scope") == "FEATURE_CODING":
                coding = item
                break
        if coding is None:
            coding = usages[0]
        detail = coding.get("detail", {}) if isinstance(coding, dict) else {}
        limit_val = _safe_int(detail.get("limit"))
        used_val = _safe_int(detail.get("used"))
        remaining_val = _safe_int(detail.get("remaining"))
        reset_time = detail.get("resetTime")
        limits = []
        for item in coding.get("limits", []) if isinstance(coding, dict) else []:
            if not isinstance(item, dict):
                continue
            window = item.get("window", {}) if isinstance(item.get("window"), dict) else {}
            d = item.get("detail", {}) if isinstance(item.get("detail"), dict) else {}
            l_limit = _safe_int(d.get("limit"))
            l_remaining = _safe_int(d.get("remaining"))
            l_used = None
            if l_limit is not None and l_remaining is not None:
                l_used = max(l_limit - l_remaining, 0)
            l_reset = d.get("resetTime")
            limits.append({
                "windowSeconds": window.get("duration"),
                "windowUnit": window.get("timeUnit"),
                "limit": str(d.get("limit")) if d.get("limit") is not None else None,
                "used": str(l_used) if l_used is not None else None,
                "remaining": str(d.get("remaining")) if d.get("remaining") is not None else None,
                "usedPercent": _percent_text(l_used, l_limit),
                "usedRatio": _ratio(l_used, l_limit),
                "resetTime": l_reset,
                "resetInHours": _hours_to_reset(l_reset),
            })
        return {
            "membership": None,
            "membershipName": None,
            "usage": {
                "scope": coding.get("scope") if isinstance(coding, dict) else None,
                "limit": str(detail.get("limit")) if detail.get("limit") is not None else None,
                "used": str(detail.get("used")) if detail.get("used") is not None else None,
                "remaining": str(detail.get("remaining")) if detail.get("remaining") is not None else None,
                "usedPercent": _percent_text(used_val, limit_val),
                "usedRatio": _ratio(used_val, limit_val),
                "resetTime": reset_time,
                "resetInHours": _hours_to_reset(reset_time),
            },
            "limits": limits,
            "source": "api",
        }
    if "usage" not in payload and "research_usage" in payload:
        membership = payload.get("membership")
        if isinstance(membership, dict):
            membership = membership.get("level")
        usage = {}
        research = payload.get("research_usage", {})
        if isinstance(research, dict):
            if "total" in research:
                usage["limit"] = str(research.get("total"))
            if "remain" in research:
                usage["remaining"] = str(research.get("remain"))
            if "date" in research:
                usage["resetDate"] = str(research.get("date"))
        return {
            "membership": str(membership) if membership is not None else None,
            "membershipName": _membership_name(membership),
            "usage": usage,
            "limits": [],
            "source": "api",
        }
    membership = payload.get("user", {}).get("membership", {}).get("level")
    membership_name = payload.get("user", {}).get("membership", {}).get("name")
    return {
        "membership": membership,
        "membershipName": membership_name if membership_name is not None else _membership_name(membership),
        "usage": payload.get("usage", {}),
        "limits": payload.get("limits", []),
        "source": "api",
    }

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

def _membership_name(level):
    if level is None:
        return None
    if str(level) == "20":
        return "Moderato"
    return str(level)

def normalize_browser_text(raw_text):
    membership = None
    usage = {}
    for line in raw_text.splitlines():
        if ":" not in line:
            continue
        key, value = line.split(":", 1)
        key = key.strip().lower()
        value = value.strip()
        if key == "membership":
            membership = value
        elif key == "limit":
            usage["limit"] = value
        elif key == "remaining":
            usage["remaining"] = value
    return {
        "membership": membership,
        "membershipName": _membership_name(membership),
        "usage": usage,
        "limits": [],
        "source": "browser",
    }

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
