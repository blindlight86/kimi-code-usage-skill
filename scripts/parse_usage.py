#!/usr/bin/env python3
import json
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
        # API timestamp example: 2026-03-10T16:22:47.523319Z
        ts = datetime.fromisoformat(str(reset_time).replace("Z", "+00:00"))
        delta = ts - datetime.now(timezone.utc)
        hours = delta.total_seconds() / 3600
        return max(round(hours, 2), 0.0)
    except Exception:
        return None


def normalize_api_payload(payload_text: str) -> dict:
    payload = json.loads(payload_text)

    # Kimi code billing service payload shape.
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
            limits.append(
                {
                    "windowSeconds": window.get("duration"),
                    "windowUnit": window.get("timeUnit"),
                    "limit": str(d.get("limit")) if d.get("limit") is not None else None,
                    "used": str(l_used) if l_used is not None else None,
                    "remaining": str(d.get("remaining")) if d.get("remaining") is not None else None,
                    "usedPercent": _percent_text(l_used, l_limit),
                    "usedRatio": _ratio(l_used, l_limit),
                    "resetTime": l_reset,
                    "resetInHours": _hours_to_reset(l_reset),
                }
            )

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

    # New Kimi web usage payload shape.
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


def normalize_browser_text(raw_text: str) -> dict:
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
