"""
Spin Python WASM 应用 — 通过 Dapr Sidecar 实现状态管理与消息发布

架构：Spin WASM (HTTP handler) + Dapr Sidecar (基础设施抽象)
业务代码只负责 HTTP 路由，所有基础设施操作通过 Dapr HTTP API 完成
"""
import json
from base64 import b64decode
from spin_sdk import http
from spin_sdk.http import IncomingHandler, Request, Response, send

DAPR_URL = "http://127.0.0.1:3500"


def dapr_http_binding(binding_name: str, path: str):
    """通过 Dapr HTTP output binding 发起请求，由 sidecar 出站"""
    body = json.dumps({"operation": "get", "metadata": {"path": path}})
    resp = send(Request("POST",
                        f"{DAPR_URL}/v1.0/bindings/{binding_name}",
                        {"content-type": "application/json"},
                        bytes(body, "utf-8")))
    if resp.status >= 400:
        raise Exception(f"binding {resp.status}: {resp.body.decode('utf-8') if resp.body else ''}")
    j = json.loads(resp.body.decode("utf-8")) if resp.body else {}
    raw = b64decode(j["data"]).decode("utf-8") if j.get("data") else ""
    try:
        return json.loads(raw)
    except (json.JSONDecodeError, ValueError):
        return raw


class IncomingHandler(IncomingHandler):
    def handle_request(self, request: Request) -> Response:
        path = request.uri
        method = request.method

        if method == "GET" and path == "/health":
            return Response(200, {"content-type": "application/json"},
                            bytes(json.dumps({"status": "healthy"}), "utf-8"))

        if method == "POST" and path == "/state":
            resp = send(Request("POST",
                                f"{DAPR_URL}/v1.0/state/statestore",
                                {"content-type": "application/json"},
                                request.body))
            return Response(resp.status, {}, resp.body)

        if method == "GET" and path.startswith("/state/"):
            key = path[len("/state/"):]
            resp = send(Request("GET",
                                f"{DAPR_URL}/v1.0/state/statestore/{key}",
                                {}, None))
            return Response(resp.status,
                            {"content-type": "application/json"},
                            resp.body)

        if method == "POST" and path.startswith("/publish/"):
            topic = path[len("/publish/"):]
            resp = send(Request("POST",
                                f"{DAPR_URL}/v1.0/publish/pubsub/{topic}",
                                {"content-type": "application/json"},
                                request.body))
            return Response(resp.status, {}, resp.body)

        if method == "GET" and path == "/check-binding":
            try:
                resp = send(Request("GET", f"{DAPR_URL}/v1.0/metadata", {}, None))
                body_str = resp.body.decode("utf-8") if resp.body else "{}"
                try:
                    parsed = json.loads(body_str)
                except (json.JSONDecodeError, ValueError):
                    parsed = body_str
                return Response(200, {"content-type": "application/json"},
                                bytes(json.dumps({
                                    "status": "ok",
                                    "target": "dapr-bindings",
                                    "daprMetadata": parsed,
                                }), "utf-8"))
            except Exception as e:
                return Response(502, {"content-type": "application/json"},
                                bytes(json.dumps({
                                    "status": "error",
                                    "target": "dapr-bindings",
                                    "error": str(e),
                                }), "utf-8"))

        if method == "GET" and path == "/consul/nodes":
            try:
                parsed = dapr_http_binding("consul-http", "/v1/catalog/nodes")
                return Response(200, {"content-type": "application/json"},
                                bytes(json.dumps({"status": "ok", "nodes": parsed}), "utf-8"))
            except Exception as e:
                return Response(502, {"content-type": "application/json"},
                                bytes(json.dumps({"status": "error", "error": str(e)}), "utf-8"))

        if method == "GET" and path == "/external/sample":
            try:
                data = dapr_http_binding("external-http", "/kuaidihelp/smscallback")
                return Response(200, {"content-type": "application/json"},
                                bytes(json.dumps({"status": "ok", "data": data}), "utf-8"))
            except Exception as e:
                return Response(502, {"content-type": "application/json"},
                                bytes(json.dumps({"status": "error", "error": str(e)}), "utf-8"))

        if method == "GET" and path == "/":
            return Response(200,
                            {"content-type": "text/html; charset=utf-8"},
                            bytes(INDEX_HTML, "utf-8"))

        return Response(404, {"content-type": "application/json"},
                        bytes(json.dumps({"error": "not found"}), "utf-8"))


INDEX_HTML = """<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>Spin Python + Dapr</title>
<style>
body { font-family: Arial, sans-serif; margin: 40px; line-height: 1.6; }
h1 { color: #3776ab; }
.info { background: #f8f9fa; padding: 20px; border-radius: 5px; }
code { background: #e9ecef; padding: 2px 5px; border-radius: 3px; }
</style>
</head>
<body>
<h1>Spin Python (WASM) + Dapr Sidecar</h1>
<div class="info">
<p>Runtime: Spin WebAssembly (Python / componentize-py)</p>
<p>Dapr HTTP: <code>3500</code> (bridge 默认端口)</p>
<p>App ID: <code>spin-python-app</code></p>
<pre>
wsl curl -s http://localhost/spin-python-app/health
</pre>
</div>
</body>
</html>"""
