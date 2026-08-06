#!/usr/bin/env python3
"""App Store Connect API helper — build status, deep-dive, and watching.

Uses an App Store Connect API key (created at
https://appstoreconnect.apple.com/access/integrations → Keys → +).
Requires: issuer ID, key ID, and the downloaded .p8 private key file.

Usage:
    python3 tool/asc_api.py apps                    # list apps (id, name, bundleId)
    python3 tool/asc_api.py builds                  # list builds (newest first)
    python3 tool/asc_api.py builds --processing     # only PROCESSING builds
    python3 tool/asc_api.py detail <build_id>       # deep-dive: state, beta, encryption
    python3 tool/asc_api.py watch [build_number]    # poll until a build is VALID/INVALID/FAILED

Everything can also live in ~/.config/finflow/asc.env (KEY=VALUE lines).
"""

import base64
import json
import os
import subprocess
import sys
import time
import urllib.request
import urllib.parse

API = "https://api.appstoreconnect.apple.com"

# Order n of the P-256 curve (SEC2). Apple rejects "high-S" ECDSA signatures,
# and OpenSSL's random nonce produces them ~50% of the time, so we normalize
# s -> n - s when s > n/2 (standard low-S normalization).
_P256_N = 0xFFFFFFFF00000000FFFFFFFFFFFFFFFFBCE6FAADA7179E84F3B9CAC2FC632551


def _load_env():
    """Merge ~/.config/finflow/asc.env (if present) into the environment."""
    env_file = os.path.expanduser("~/.config/finflow/asc.env")
    if os.path.isfile(env_file):
        with open(env_file, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#") and "=" in line:
                    k, v = line.split("=", 1)
                    os.environ.setdefault(k.strip(), v.strip())


def _b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def _der_to_raw(der: bytes) -> bytes:
    """Convert a DER-encoded ECDSA signature (r,s) into raw r||s (64 bytes).

    DER integers may be 33 bytes when the high bit is set (a leading 0x00
    marker) — strip that before padding to the fixed 32-byte JWT width.
    """
    # Expect: 0x30 <len> 0x02 <len> <r> 0x02 <len> <s>
    assert der[0] == 0x30, "not a DER sequence"
    i = 2  # skip 30 <len>
    assert der[i] == 0x02
    r_len = der[i + 1]
    r = der[i + 2 : i + 2 + r_len]
    i = i + 2 + r_len
    assert der[i] == 0x02
    s_len = der[i + 1]
    s = der[i + 2 : i + 2 + s_len]
    i = i + 2 + s_len
    assert i == len(der), "trailing DER bytes"

    def _to32(v: bytes) -> bytes:
        v = v.lstrip(b"\x00") or b"\x00"
        return v.rjust(32, b"\x00")

    return _to32(r) + _to32(s)


def _sign(data: bytes, key_path: str) -> bytes:
    """Sign data with the .p8 key via openssl, return raw 64-byte ECDSA sig
    normalized to a low-S form (required by the App Store Connect API)."""
    proc = subprocess.run(
        ["openssl", "dgst", "-sha256", "-sign", key_path],
        input=data,
        capture_output=True,
    )
    if proc.returncode != 0:
        raise RuntimeError(f"openssl signing failed: {proc.stderr.decode()}")
    raw = _der_to_raw(proc.stdout)
    r, s = raw[:32], raw[32:]
    s_int = int.from_bytes(s, "big")
    if s_int > _P256_N // 2:
        s = (_P256_N - s_int).to_bytes(32, "big")
    return r + s


def _jwt(issuer: str, key_id: str, key_path: str) -> str:
    header = _b64url(json.dumps({"alg": "ES256", "kid": key_id, "typ": "JWT"}, separators=(",", ":")).encode())
    now = int(time.time())
    payload = _b64url(
        json.dumps(
            {"iss": issuer, "iat": now, "exp": now + 1190, "aud": "appstoreconnect-v1"},
            separators=(",", ":"),
        ).encode()
    )
    signing_input = f"{header}.{payload}".encode()
    return f"{header}.{payload}.{_b64url(_sign(signing_input, key_path))}"


def _request(token: str, path: str) -> dict:
    req = urllib.request.Request(
        f"{API}{path}", headers={"Authorization": f"Bearer {token}"}
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read().decode())


def _fmt_build(b: dict) -> str:
    a = b.get("attributes", {})
    state = a.get("processingState", "?")
    beta = a.get("betaReviewState", "?")
    expires = a.get("expirationDate", "")
    uploaded = (a.get("uploadedDate") or "")[:19].replace("T", " ")
    # The ASC API exposes the build number as "version".
    number = a.get("version") or a.get("buildNumber") or "?"
    return (
        f"  build 0.1.0 ({number})  id={b.get('id','?'):<12}  "
        f"state={state:<10} beta={beta:<12} uploaded={uploaded}"
        + (f"  expires={expires[:10]}" if expires else "")
    )


def _build_number(b: dict) -> str:
    a = b.get("attributes", {})
    return str(a.get("version") or a.get("buildNumber") or "?")


def _cmd_detail(token: str, build_id: str, app_id: str) -> int:
    path = f"/v1/builds/{urllib.parse.quote(build_id)}?include=buildBetaDetail,betaAppReviewSubmission,betaGroups,appEncryptionDeclaration"
    data = _request(token, path)
    # Single-resource endpoints return data as a dict, list endpoints as an array.
    raw = data.get("data")
    b = raw if isinstance(raw, dict) else (raw[0] if raw else None)
    if not b:
        print(f"  build {build_id} not found")
        return 1
    a = b.get("attributes", {})
    print("  ── Build ──────────────────────────────────────────")
    print(f"  id:                 {b.get('id')}")
    print(f"  version:            {a.get('version', '?')}")
    print(f"  processingState:    {a.get('processingState', '?')}")
    print(f"  uploadedDate:       {(a.get('uploadedDate') or '?')[:19].replace('T', ' ')}")
    print(f"  expirationDate:     {(a.get('expirationDate') or '?')[:10]}")
    print(f"  expired:            {a.get('expired', '?')}")
    print(f"  minOsVersion:       {a.get('minOsVersion', '?')}")
    print(
        "  usesNonExemptEncryption: "
        + str(a.get("usesNonExemptEncryption", "?"))
        + "   (False = export compliance answered 'No')"
    )
    print(f"  buildAudienceType:  {a.get('buildAudienceType', '?')}")

    included = {item.get("type"): item for item in data.get("included", [])}

    bbd = included.get("buildBetaDetail")
    if bbd:
        x = bbd.get("attributes", {})
        print("  ── Beta detail ─────────────────────────────────────")
        print(f"  internalState:      {x.get('internalState', '?')}")
        print(f"  externalState:      {x.get('externalState', '?')}")
        print(f"  autoNotifyEnabled:  {x.get('autoNotifyEnabled', '?')}")

    bas = included.get("betaAppReviewSubmission")
    if bas:
        x = bas.get("attributes", {})
        print("  ── Beta app review ────────────────────────────────")
        print(f"  betaReviewState:    {x.get('betaReviewState', '?')}")

    groups = [g for g in data.get("included", []) if g.get("type") == "betaGroups"]
    if groups:
        print("  ── Beta groups ─────────────────────────────────────")
        for g in groups:
            ga = g.get("attributes", {})
            print(f"  • {ga.get('name', '?')}  (publicLinkEnabled={ga.get('publicLinkEnabled', '?')})")
    else:
        print("  beta groups:        none")

    enc = included.get("appEncryptionDeclaration")
    if enc:
        x = enc.get("attributes", {})
        print("  ── Encryption declaration ──────────────────────────")
        print(f"  usesEncryption:     {x.get('usesEncryption', '?')}")
        print(f"  appEncryptionState: {x.get('appEncryptionState', '?')}")
        print(f"  documentName:       {x.get('documentName', '?')}")
    return 0


def main() -> int:
    _load_env()
    issuer = os.environ.get("ASC_ISSUER")
    key_id = os.environ.get("ASC_KEY_ID")
    key_path = os.environ.get("ASC_KEY_PATH")
    if not (issuer and key_id and key_path):
        print(
            "Missing credentials. Set ASC_ISSUER, ASC_KEY_ID, ASC_KEY_PATH "
            "(or ~/.config/finflow/asc.env).",
            file=sys.stderr,
        )
        return 2
    if not os.path.isfile(key_path):
        print(f"Key file not found: {key_path}", file=sys.stderr)
        return 2

    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    cmd = args[0] if args else "builds"
    processing_only = "--processing" in sys.argv

    token = _jwt(issuer, key_id, key_path)
    app_id = os.environ.get("ASC_APP_ID")

    try:
        if cmd == "apps":
            data = _request(token, "/v1/apps?limit=200")
            for app in data.get("data", []):
                attrs = app.get("attributes", {})
                print(f"  {app['id']}  {attrs.get('name','?')}  {attrs.get('bundleId','?')}")
            return 0

        if cmd == "detail":
            if len(args) < 2:
                print("usage: python3 tool/asc_api.py detail <build_id>", file=sys.stderr)
                return 2
            return _cmd_detail(token, args[1], app_id)

        if cmd == "watch":
            target = args[1] if len(args) > 1 else None
            deadline = time.time() + int(os.environ.get("ASC_WATCH_TIMEOUT", "1800"))
            seen = set()
            while time.time() < deadline:
                q = "?limit=50&sort=-uploadedDate"
                if app_id:
                    q += f"&filter[app]={urllib.parse.quote(app_id)}"
                data = _request(token, f"/v1/builds{q}")
                builds = data.get("data", [])
                for b in builds:
                    num = _build_number(b)
                    st = b.get("attributes", {}).get("processingState", "?")
                    if num not in seen:
                        print(_fmt_build(b))
                        seen.add(num)
                    if target is not None and num != target:
                        continue
                    if st in ("VALID", "INVALID", "FAILED"):
                        print(f"\n  → build {num} finished: {st}")
                        return 0
                if target is not None:
                    found = any(_build_number(b) == target for b in builds)
                    if not found:
                        print(f"  … build {target} not visible yet, checking again in 30s")
                else:
                    print("  … still processing, checking again in 30s")
                time.sleep(30)
            print("  timeout: target build not finished", file=sys.stderr)
            return 1

        # default: list builds
        q = "?limit=50&sort=-uploadedDate"
        if app_id:
            q += f"&filter[app]={urllib.parse.quote(app_id)}"
        if processing_only:
            q += "&filter[processingState]=PROCESSING"
        data = _request(token, f"/v1/builds{q}")
        builds = data.get("data", [])
        if not builds:
            print("  no builds found")
            return 0
        for b in builds:
            print(_fmt_build(b))
        return 0
    except urllib.error.HTTPError as e:
        body = e.read().decode()[:400]
        print(f"HTTP {e.code}: {body}", file=sys.stderr)
        return 1
    except Exception as e:  # noqa: BLE001
        print(f"error: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
