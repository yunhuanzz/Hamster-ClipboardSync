#!/usr/bin/env python3
"""剪贴板同步参考服务端 (极简版, 与 Hamster 剪贴板同步功能配套).

协议:
  PUT /  Body 为纯文本剪贴板内容  -> 保存为"最新一条"
  GET /  返回最新一条剪贴板内容 (纯文本; 无内容时返回 204)
鉴权: 若设置了 USERNAME/PASSWORD 环境变量, 则要求 HTTP Basic Auth。

用法:
  USERNAME=yunhuan PASSWORD=xxxx python3 clipboard-sync-server.py
  # 默认监听 127.0.0.1:5033, 用 --host/--port 修改
  # 放在公网时请务必用反向代理套 HTTPS (如 Caddy/Nginx), 不要直接暴露 HTTP。

依赖: 仅 Python 3 标准库。
"""

import argparse
import base64
import os
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HOST = os.environ.get("HOST", "127.0.0.1")
PORT = int(os.environ.get("PORT", "5033"))
USERNAME = os.environ.get("USERNAME", "")
PASSWORD = os.environ.get("PASSWORD", "")

_lock = threading.Lock()
_latest = ""


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def _auth_ok(self) -> bool:
        if not USERNAME:
            return True
        auth = self.headers.get("Authorization", "")
        if not auth.startswith("Basic "):
            return False
        try:
            decoded = base64.b64decode(auth[6:]).decode("utf-8")
        except Exception:
            return False
        return decoded == f"{USERNAME}:{PASSWORD}"

    def _require_auth(self):
        self.send_response(401)
        self.send_header("WWW-Authenticate", 'Basic realm="ClipboardSync"')
        self.send_header("Content-Length", "0")
        self.end_headers()

    def do_GET(self):
        if not self._auth_ok():
            self._require_auth()
            return
        with _lock:
            body = _latest.encode("utf-8")
        if not body:
            self.send_response(204)
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_PUT(self):
        if not self._auth_ok():
            self._require_auth()
            return
        length = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(length) if length > 0 else b""
        text = raw.decode("utf-8", errors="replace")
        with _lock:
            global _latest
            _latest = text
        self.send_response(200)
        self.send_header("Content-Length", "0")
        self.end_headers()

    def log_message(self, fmt, *args):
        pass


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Clipboard sync reference server")
    parser.add_argument("--host", default=HOST)
    parser.add_argument("--port", type=int, default=PORT)
    args = parser.parse_args()
    server = ThreadingHTTPServer((args.host, args.port), Handler)
    print(f"ClipboardSync server listening on {args.host}:{args.port} (auth={'on' if USERNAME else 'off'})")
    server.serve_forever()
