import json
from spin_sdk import http
from spin_sdk.http import IncomingHandler, Request, Response, send

DAPR_URL = "http://127.0.0.1:3506"


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
<p>Dapr HTTP: <code>3506</code></p>
<p>App ID: <code>spin-python-app</code></p>
<pre>
curl http://localhost:3506/v1.0/invoke/spin-python-app/method/health
</pre>
</div>
</body>
</html>"""
