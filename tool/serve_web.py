#!/usr/bin/env python3
"""Serve build/web with the MIME types the SQLite WASM build needs
(.wasm -> application/wasm) and no-cache headers.

Usage: python3 tool/serve_web.py [port]
"""

import http.server
import os
import sys

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "build", "web")

EXTRA_MIME = {
    ".wasm": "application/wasm",
    ".js": "application/javascript",
    ".json": "application/json",
    ".ttf": "font/ttf",
    ".otf": "font/otf",
    ".gz": "application/gzip",
}


class NoCacheHandler(http.server.SimpleHTTPRequestHandler):
    extensions_map = {
        **http.server.SimpleHTTPRequestHandler.extensions_map,
        **EXTRA_MIME,
    }

    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=ROOT, **kwargs)

    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def send_head(self):
        # SPA fallback: unknown paths (client-side routes like /analytics)
        # serve index.html so go_router can handle them.
        if not os.path.isfile(self.translate_path(self.path)):
            self.path = "/index.html"
        return super().send_head()


if __name__ == "__main__":
    print(f"serving {ROOT} on http://localhost:{PORT}")
    http.server.ThreadingHTTPServer(("127.0.0.1", PORT), NoCacheHandler).serve_forever()
