"""
本地模拟华为云 FunctionGraph（免费额度用尽 / 未部署时也能演示“云端计算”）。

用法：
    python scripts/mock_fg.py [port]      # 默认 9100
然后用 FG_ENDPOINT=http://127.0.0.1:9100/billing 启动后端。

路由：
    POST /billing           → cloud/functiongraph/billing/billing.py 的 handler
    POST /timeout_release   → cloud/functiongraph/timeout_release/timeout_release.py 的 handler
    GET  /health            → {"status": "UP"}

它和云端部署的是同一份 handler 代码，所以本地演示与线上结果一致。
"""
import json
import os
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "cloud", "functiongraph", "billing"))
sys.path.insert(0, os.path.join(ROOT, "cloud", "functiongraph", "timeout_release"))

import billing  # noqa: E402
import timeout_release  # noqa: E402


class Handler(BaseHTTPRequestHandler):
    server_version = "MockFunctionGraph/1.0"

    def _read_body(self):
        length = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(length) if length else b""
        try:
            return json.loads(raw.decode("utf-8")) if raw else {}
        except json.JSONDecodeError:
            return {}

    def _send(self, status, payload):
        data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path.startswith("/health"):
            self._send(200, {"status": "UP", "service": "mock-functiongraph"})
        else:
            self._send(404, {"error": "not found"})

    def do_POST(self):
        body = self._read_body()
        if self.path.startswith("/billing"):
            result = billing.handler({"body": json.dumps(body)}, None)
        elif self.path.startswith("/timeout_release"):
            result = timeout_release.handler({"time": None}, None)
        else:
            self._send(404, {"error": "not found"})
            return
        status = int(result.get("statusCode", 200))
        payload = result.get("body")
        try:
            payload = json.loads(payload) if isinstance(payload, str) else payload
        except json.JSONDecodeError:
            pass
        self._send(status, payload)

    def log_message(self, fmt, *args):
        sys.stderr.write("[mock-fg] " + (fmt % args) + "\n")


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 9100
    print("mock FunctionGraph listening on http://127.0.0.1:%d" % port, flush=True)
    ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()
