"""Verify a deployed FunctionGraph billing endpoint against the backend's contract.

Usage:
    python scripts/check_fg.py https://<your-http-trigger-url>
    python scripts/check_fg.py http://127.0.0.1:9100/billing

The backend (CloudBillingClient) POSTs {"unitPrice": "4.00", "minutes": 30}
and expects either {"amount": "2.00", ...} or a FunctionGraph-style
{"body": "{\\"amount\\": ...}"} wrapper. This script checks both shapes.
"""
import json
import sys
import urllib.request
import urllib.error

CASES = [
    (4.00, 30, "2.00"),
    (4.80, 30, "2.40"),
]


def post(url, unit_price, minutes):
    payload = json.dumps({"unitPrice": str(unit_price), "minutes": minutes}).encode("utf-8")
    req = urllib.request.Request(url, data=payload, method="POST")
    req.add_header("Content-Type", "application/json")
    with urllib.request.urlopen(req, timeout=10) as resp:
        raw = resp.read().decode("utf-8")
        return resp.status, json.loads(raw)


def extract_amount(obj):
    """Accept the same shapes as CloudBillingClient does."""
    if isinstance(obj, dict):
        if "amount" in obj:
            return str(obj["amount"])
        if "body" in obj:
            body = obj["body"]
            if isinstance(body, str):
                try:
                    return extract_amount(json.loads(body))
                except json.JSONDecodeError:
                    return None
            return extract_amount(body)
    return None


def main():
    if len(sys.argv) < 2:
        print("usage: python scripts/check_fg.py <FG_ENDPOINT>")
        return 2
    url = sys.argv[1]
    ok = True
    for unit_price, minutes, expected in CASES:
        try:
            status, body = post(url, unit_price, minutes)
            amount = extract_amount(body)
            passed = status == 200 and amount is not None and float(amount) == float(expected)
            ok &= passed
            print("%s  %.2f x %d min -> %s (expected %s)  [%s]" % (
                "PASS" if passed else "FAIL", unit_price, minutes, amount, expected,
                "status %s" % status))
        except Exception as exc:
            ok = False
            print("FAIL  %.2f x %d min -> %s: %s" % (unit_price, minutes, type(exc).__name__, exc))
    print("\nRESULT: %s" % ("OK - backend can use this FG_ENDPOINT" if ok else "NOT READY"))
    if not ok:
        print("Check: HTTP trigger method is POST, auth is None, entry is billing.handler,")
        print("      and the body must contain an 'amount' field (or an APIG 'body' wrapper).")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
