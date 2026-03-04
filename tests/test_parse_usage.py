from scripts.parse_usage import normalize_api_payload, normalize_browser_text


def test_normalize_api_payload_basic():
    payload = '{"usage":{"limit":"100","remaining":"74","resetTime":"2026-02-11T17:32:50Z"},"limits":[],"user":{"membership":{"level":"LEVEL_INTERMEDIATE"}}}'
    result = normalize_api_payload(payload)
    assert result["membership"] == "LEVEL_INTERMEDIATE"
    assert result["membershipName"] == "LEVEL_INTERMEDIATE"
    assert result["usage"]["limit"] == "100"


def test_normalize_browser_text_basic():
    text = "Membership: LEVEL_BASIC\nLimit: 80\nRemaining: 21\n"
    result = normalize_browser_text(text)
    assert result["membership"] == "LEVEL_BASIC"
    assert result["membershipName"] == "LEVEL_BASIC"
    assert result["usage"]["limit"] == "80"
    assert result["usage"]["remaining"] == "21"
    assert result["source"] == "browser"


def test_normalize_api_payload_web_usage_shape():
    payload = '{"research_usage":{"total":50,"remain":49,"date":"2026-03-04"},"membership":{"level":20}}'
    result = normalize_api_payload(payload)
    assert result["membership"] == "20"
    assert result["membershipName"] == "Moderato"
    assert result["usage"]["limit"] == "50"
    assert result["usage"]["remaining"] == "49"
    assert result["usage"]["resetDate"] == "2026-03-04"


def test_normalize_api_payload_billing_usage_shape():
    payload = (
        '{"usages":[{"scope":"FEATURE_CODING","detail":{"limit":"100","used":"4","remaining":"96",'
        '"resetTime":"2099-03-10T16:22:47.523319Z"},"limits":[{"window":{"duration":300,'
        '"timeUnit":"TIME_UNIT_MINUTE"},"detail":{"limit":"100","remaining":"100",'
        '"resetTime":"2099-03-04T12:22:47.523319Z"}}]}]}'
    )
    result = normalize_api_payload(payload)
    assert result["usage"]["scope"] == "FEATURE_CODING"
    assert result["membershipName"] is None
    assert result["usage"]["limit"] == "100"
    assert result["usage"]["used"] == "4"
    assert result["usage"]["remaining"] == "96"
    assert result["usage"]["usedPercent"] == 4.0
    assert result["usage"]["resetInHours"] is not None
    assert result["limits"][0]["windowSeconds"] == 300
    assert result["limits"][0]["usedPercent"] == 0.0
