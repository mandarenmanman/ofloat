use spin_sdk::http::{IntoResponse, Request, Response};
use spin_sdk::http_component;

#[http_component]
fn handle_request(req: Request) -> anyhow::Result<impl IntoResponse> {
    let path = req.path();
    println!("Handling request to {}", path);

    match path {
        "/health" => Ok(Response::builder()
            .status(200)
            .header("content-type", "application/json")
            .body(r#"{"status":"healthy"}"#)
            .build()),
        _ => Ok(Response::builder()
            .status(200)
            .header("content-type", "text/html; charset=utf-8")
            .body(INDEX_HTML)
            .build()),
    }
}

const INDEX_HTML: &str = r#"<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>Spin with Dapr Sidecar</title>
<style>
body { font-family: Arial, sans-serif; margin: 40px; line-height: 1.6; }
h1 { color: #0d6efd; }
.info { background: #f8f9fa; padding: 20px; border-radius: 5px; }
code { background: #e9ecef; padding: 2px 5px; border-radius: 3px; }
</style>
</head>
<body>
<h1>🚀 Spin (Wasm) with Dapr Sidecar</h1>
<div class="info">
<p><strong>运行时：</strong> Spin WebAssembly (Rust)</p>
<p><strong>Dapr HTTP 端口：</strong> <code>3500</code></p>
<p><strong>应用 ID：</strong> <code>spin-app</code></p>
<p><strong>调用示例：</strong></p>
<pre>
# 通过 Dapr 调用
curl http://localhost:3500/v1.0/invoke/spin-app/method/

# 健康检查
curl http://localhost:3500/v1.0/invoke/spin-app/method/health

# Dapr 元数据
curl http://localhost:3500/v1.0/metadata
</pre>
</div>
</body>
</html>"#;
