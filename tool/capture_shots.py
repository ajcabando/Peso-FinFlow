#!/usr/bin/env python3
"""App Store screenshots via CDP — FINAL.

Key fixes vs earlier attempts:
- Dashboard route is `/` (NOT `#/dashboard` — that path doesn't exist and
  go_router renders a blank page for it).
- `--enable-unsafe-swiftshader` gives CanvasKit real WebGL (no CPU fallback).
- Light mode forced so every shot matches.
- One tab per device; routes navigated in-tab (SPA hash changes).

Usage: python3 tool/capture_shots.py
"""

import base64
import io
import json
import os
import shutil
import subprocess
import sys
import time
import urllib.request

from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
OUT = os.path.join(ROOT, "dist", "screenshots")
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
PORT = 9239

# (route_or_url, outname, width, height, mobile)
IPHONE = [
    ("/", "iphone-6.7-dashboard", 1290, 2796, True),
    ("#/analytics", "iphone-6.7-analytics", 1290, 2796, True),
    ("#/transactions", "iphone-6.7-transactions", 1290, 2796, True),
    ("#/accounts", "iphone-6.7-accounts", 1290, 2796, True),
]
IPAD = [
    ("/", "ipad-12.9-dashboard", 2048, 2732, False),
    ("#/analytics", "ipad-12.9-analytics", 2048, 2732, False),
    ("#/transactions", "ipad-12.9-transactions", 2048, 2732, False),
]

BOOT_WAIT = 90   # first route: cold boot + seeding
ROUTE_WAIT = 20  # subsequent in-tab navigations
SETTLE = 6       # extra seconds after first paint so animations finish


def start_server():
    subprocess.run(["pkill", "-f", "serve_web.py"], capture_output=True)
    time.sleep(1)
    proc = subprocess.Popen(
        [sys.executable, os.path.join(ROOT, "tool", "serve_web.py"), "8080"],
        stdout=open("/tmp/web_server.log", "w"),
        stderr=subprocess.STDOUT,
    )
    for _ in range(40):
        try:
            urllib.request.urlopen("http://localhost:8080/", timeout=2)
            return proc
        except Exception:
            time.sleep(0.5)
    print("SERVER FAILED")
    sys.exit(1)


def launch_chrome():
    subprocess.run(["pkill", "-9", "-f", "Google Chrome"], capture_output=True)
    time.sleep(1)
    profile = "/tmp/ff_capture_profile"
    shutil.rmtree(profile, ignore_errors=True)
    return subprocess.Popen(
        [
            CHROME, "--headless=new", "--enable-unsafe-swiftshader",
            f"--remote-debugging-port={PORT}", "--remote-allow-origins=*",
            f"--user-data-dir={profile}", "--no-first-run", "about:blank",
        ],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def get_ws_url():
    for _ in range(60):
        try:
            with urllib.request.urlopen(f"http://127.0.0.1:{PORT}/json/version", timeout=2) as r:
                return json.loads(r.read())["webSocketDebuggerUrl"]
        except Exception:
            time.sleep(0.25)
    raise RuntimeError("Chrome DevTools not reachable")


class Tab:
    def __init__(self, ws):
        self.ws = ws
        self.id = 0

    def call(self, method, params=None):
        self.id += 1
        self.ws.send(json.dumps({"id": self.id, "method": method, "params": params or {}}))
        while True:
            m = json.loads(self.ws.recv())
            if m.get("id") == self.id:
                if "error" in m:
                    raise RuntimeError(f"{method}: {m['error']}")
                return m.get("result", {})


def new_tab(ws_url, w, h, mobile):
    import websocket
    req = urllib.request.Request(f"http://127.0.0.1:{PORT}/json/new?about:blank", method="PUT")
    with urllib.request.urlopen(req) as r:
        tab = json.loads(r.read())
    ws = websocket.create_connection(tab["webSocketDebuggerUrl"], timeout=180)
    t = Tab(ws)
    t.call("Page.enable")
    t.call("Emulation.setDeviceMetricsOverride", {
        "width": w, "height": h, "deviceScaleFactor": 1,
        "mobile": mobile, "screenWidth": w, "screenHeight": h,
    })
    return t


def shot(tab):
    r = tab.call("Page.captureScreenshot", {"format": "png", "fromSurface": True})
    return base64.b64decode(r["data"])


def stats(data):
    im = Image.open(io.BytesIO(data)).convert("RGB")
    w, h = im.size
    px = im.load()
    tot = dark = colorful = 0
    for y in range(0, h, 12):
        for x in range(0, w, 12):
            r, g, b = px[x, y]
            tot += 1
            if r + g + b < 300:
                dark += 1
            if max(r, g, b) - min(r, g, b) > 30:
                colorful += 1
    return w, h, dark / tot, colorful / tot


def capture_device(ws_url, shots, device_name):
    w = shots[0][2]
    h = shots[0][3]
    mobile = shots[0][4]
    tab = new_tab(ws_url, w, h, mobile)
    results = []
    for i, (route, name, _, _, _) in enumerate(shots):
        url = f"http://localhost:8080/{route}"
        if i == 0:
            tab.call("Page.navigate", {"url": url})
        else:
            tab.call("Runtime.evaluate", {"expression": f"location.hash = '{route}'"})
        cap = BOOT_WAIT if i == 0 else ROUTE_WAIT
        deadline = time.time() + cap
        data = None
        good = False
        last = None
        while time.time() < deadline:
            time.sleep(4)
            try:
                data = shot(tab)
                _, _, dark, colorful = stats(data)
                last = (dark, colorful)
                # Light mode: real content = some text (dark) + brand gradient (colorful).
                if colorful >= 0.01 and 0.005 <= dark <= 0.995:
                    good = True
                    break
            except Exception:
                continue
        if good:
            time.sleep(SETTLE)  # let entry animations finish
            try:
                data = shot(tab)
            except Exception:
                pass
        out = os.path.join(OUT, f"{name}.png")
        if data:
            with open(out, "wb") as f:
                f.write(data)
        if last is None:
            try:
                last = stats(data)[2:] if data else (0, 0)
            except Exception:
                last = (0, 0)
        results.append((name, w, h, last[0], last[1], good))
        print(f"  {device_name} {name}: dark={last[0]:.1%} colorful={last[1]:.1%} "
              f"{'OK' if good else 'FAIL'}")
    try:
        tab.ws.close()
    except Exception:
        pass
    return results


def main():
    os.makedirs(OUT, exist_ok=True)
    server = start_server()
    chrome = launch_chrome()
    ws_url = get_ws_url()

    all_results = []
    print("=== iPhone 6.7\" ===")
    all_results += capture_device(ws_url, IPHONE, "iphone-6.7")
    print("=== iPad 12.9\" ===")
    all_results += capture_device(ws_url, IPAD, "ipad-12.9")

    chrome.kill()
    server.kill()
    print("\n=== SUMMARY ===")
    for name, w, h, dark, colorful, ok in all_results:
        print(f"{name}: {'PASS' if ok else 'FAIL'} ({w}x{h} dark={dark:.1%} colorful={colorful:.1%})")


if __name__ == "__main__":
    main()
