---
name: kimi-code-usage
description: Fetch Kimi Code usage, quota, limit, and billing details with stable JSON output, including token refresh flows. Use this skill whenever the user asks about Kimi usage/quota/remaining limit/billing, token refresh, QR login bootstrap, or debugging Kimi auth failures (401/expired token/missing credentials), even if they do not explicitly mention this skill name.
---

# kimi-code-usage

Retrieve and normalize Kimi Code usage with API-first execution and QR-based login recovery.

## When To Use
- User asks for Kimi usage, remaining quota, limits, or membership usage details.
- User reports token/auth issues (`401`, token expired, cannot read usage).
- User asks to bootstrap or refresh Kimi login credentials using QR code.
- User asks for safe debug output without leaking tokens.

## Execution Workflow
1. Run credential precheck:
   - `bash scripts/get_kimi_usage.sh --check-credentials`
2. If missing/expired credentials, refresh via QR flow:
   - `bash scripts/refresh_kimi_token.sh --refresh`
   - QR screenshot path: `docs/screenshots/kimi-login-qr.png`
3. Query usage via API:
   - `bash scripts/get_kimi_usage.sh --api-only`
4. For normal user-facing result:
   - `bash scripts/get_kimi_usage.sh`
5. For troubleshooting:
   - `bash scripts/get_kimi_usage.sh --debug --api-only`

## Report Structure
Always return normalized JSON with this shape:

```json
{
  "membership": "string|null",
  "usage": {
    "limit": "string",
    "remaining": "string",
    "resetDate": "YYYY-MM-DD"
  },
  "limits": [],
  "source": "api|browser"
}
```

## Commands
- `bash scripts/bootstrap_kimi_login.sh`
- `bash scripts/refresh_kimi_token.sh --refresh`
- `bash scripts/get_kimi_usage.sh --api-only`
- `bash scripts/get_kimi_usage.sh --check-credentials`
- `bash scripts/get_kimi_usage.sh --debug --api-only`
- `bash scripts/get_kimi_usage.sh`

## Security Rules
- Never output raw `access_token` or `refresh_token`.
- Debug output must remain redacted.
- Persist credentials only to `~/.kimi/credentials/kimi-code.json`.
- Enforce `chmod 600` on credential file.
