use anyhow::Result;
use spin_sdk::http::{IntoResponse, Method, Request, Response};
use spin_sdk::http::{send, Request as OutboundRequest};
use spin_sdk::http_component;

const DAPR_URL: &str = "http://127.0.0.1:3500";

/// 通过 Dapr HTTP output binding 发起请求，由 sidecar 出站
fn dapr_http_binding_request(binding_name: &str, path: &str) -> OutboundRequest {
    let body = format!(
        r#"{{"operation":"get","metadata":{{"path":"{}"}}}}"#,
        path
    );
    OutboundRequest::builder()
        .method(Method::Post)
        .uri(&format!("{}/v1.0/bindings/{}", DAPR_URL, binding_name))
        .header("content-type", "application/json")
        .body(body)
        .build()
}

fn json_response(status: u16, body: &str) -> Response {
    Response::builder()
        .status(status)
        .header("content-type", "application/json")
        .body(body)
        .build()
}

fn method_str(m: &Method) -> &'static str {
    match m {
        Method::Get => "GET",
        Method::Post => "POST",
        Method::Put => "PUT",
        Method::Delete => "DELETE",
        Method::Patch => "PATCH",
        Method::Head => "HEAD",
        Method::Options => "OPTIONS",
        _ => "OTHER",
    }
}

#[http_component]
async fn handle_request(req: Request) -> Result<impl IntoResponse> {
    let path = req.path().to_string();
    let method = method_str(req.method());

    match (method, path.as_str()) {
        ("GET", "/health") => Ok(json_response(200, r#"{"status":"healthy"}"#)),

        ("POST", "/state") => {
            let body = req.into_body();
            let dapr_req = OutboundRequest::builder()
                .method(Method::Post)
                .uri(&format!("{}/v1.0/state/statestore", DAPR_URL))
                .header("content-type", "application/json")
                .body(body)
                .build();
            let resp: Response = send(dapr_req).await?;
            Ok(Response::builder()
                .status(*resp.status())
                .body(resp.into_body())
                .build())
        }

        ("GET", p) if p.starts_with("/state/") => {
            let key = &p[7..];
            let dapr_req = OutboundRequest::builder()
                .method(Method::Get)
                .uri(&format!("{}/v1.0/state/statestore/{}", DAPR_URL, key))
                .build();
            let resp: Response = send(dapr_req).await?;
            Ok(Response::builder()
                .status(*resp.status())
                .header("content-type", "application/json")
                .body(resp.into_body())
                .build())
        }

        ("POST", p) if p.starts_with("/publish/") => {
            let topic = &p[9..];
            let body = req.into_body();
            let dapr_req = OutboundRequest::builder()
                .method(Method::Post)
                .uri(&format!("{}/v1.0/publish/pubsub/{}", DAPR_URL, topic))
                .header("content-type", "application/json")
                .body(body)
                .build();
            let resp: Response = send(dapr_req).await?;
            Ok(Response::builder()
                .status(*resp.status())
                .body(resp.into_body())
                .build())
        }

        ("GET", "/check-binding") => {
            let dapr_req = OutboundRequest::builder()
                .method(Method::Get)
                .uri(&format!("{}/v1.0/metadata", DAPR_URL))
                .build();
            let result: Result<Response, _> = send(dapr_req).await;
            match result {
                Ok(resp) => {
                    let body_bytes = resp.into_body();
                    let body_str = String::from_utf8_lossy(&body_bytes);
                    let result = format!(
                        r#"{{"status":"ok","target":"dapr-bindings","daprMetadata":{}}}"#,
                        body_str
                    );
                    Ok(json_response(200, &result))
                }
                Err(e) => {
                    let result = format!(
                        r#"{{"status":"error","target":"dapr-bindings","error":"{}"}}"#,
                        e
                    );
                    Ok(json_response(502, &result))
                }
            }
        }

        ("GET", "/consul/nodes") => {
            let dapr_req = dapr_http_binding_request("consul-http", "/v1/catalog/nodes");
            let result: Result<Response, _> = send(dapr_req).await;
            match result {
                Ok(resp) => {
                    let body_bytes = resp.into_body();
                    let body_str = String::from_utf8_lossy(&body_bytes);
                    let parsed = parse_binding_response(&body_str);
                    let result = format!(r#"{{"status":"ok","nodes":{}}}"#, parsed);
                    Ok(json_response(200, &result))
                }
                Err(e) => {
                    let result = format!(r#"{{"status":"error","error":"{}"}}"#, e);
                    Ok(json_response(502, &result))
                }
            }
        }

        ("GET", "/external/sample") => {
            let dapr_req =
                dapr_http_binding_request("external-http", "/kuaidihelp/smscallback");
            let result: Result<Response, _> = send(dapr_req).await;
            match result {
                Ok(resp) => {
                    let body_bytes = resp.into_body();
                    let body_str = String::from_utf8_lossy(&body_bytes);
                    let parsed = parse_binding_response(&body_str);
                    let result = format!(r#"{{"status":"ok","data":{}}}"#, parsed);
                    Ok(json_response(200, &result))
                }
                Err(e) => {
                    let result = format!(r#"{{"status":"error","error":"{}"}}"#, e);
                    Ok(json_response(502, &result))
                }
            }
        }

        ("GET", "/") => Ok(Response::builder()
            .status(200)
            .header("content-type", "text/html; charset=utf-8")
            .body(INDEX_HTML)
            .build()),

        _ => Ok(json_response(404, r#"{"error":"not found"}"#)),
    }
}

/// 解析 Dapr HTTP binding 响应：{ "data": "<base64>" } -> 解码后的字符串
fn parse_binding_response(body: &str) -> String {
    if let Some(start) = body.find(r#""data":"#) {
        let after = &body[start + 7..];
        if after.starts_with("null") {
            return r#""""#.to_string();
        }
        if after.starts_with('"') {
            if let Some(end) = after[1..].find('"') {
                let b64 = &after[1..end + 1];
                if let Ok(decoded) = base64_decode(b64) {
                    return decoded;
                }
            }
        }
    }
    body.to_string()
}

/// 简易 base64 解码（标准字母表，无 padding 也兼容）
fn base64_decode(input: &str) -> Result<String> {
    let input = input.trim_end_matches('=');
    let table: Vec<u8> = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
        .iter()
        .copied()
        .collect();
    let mut buf: u32 = 0;
    let mut bits: u32 = 0;
    let mut out = Vec::new();
    for &b in input.as_bytes() {
        let val = table.iter().position(|&c| c == b);
        match val {
            Some(v) => {
                buf = (buf << 6) | v as u32;
                bits += 6;
                if bits >= 8 {
                    bits -= 8;
                    out.push((buf >> bits) as u8);
                    buf &= (1 << bits) - 1;
                }
            }
            None => anyhow::bail!("invalid base64 char"),
        }
    }
    Ok(String::from_utf8_lossy(&out).to_string())
}

const INDEX_HTML: &str = r#"<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>Spin Rust + Dapr</title>
<style>
body { font-family: Arial, sans-serif; margin: 40px; line-height: 1.6; }
h1 { color: #dea584; }
.info { background: #f8f9fa; padding: 20px; border-radius: 5px; }
code { background: #e9ecef; padding: 2px 5px; border-radius: 3px; }
</style>
</head>
<body>
<h1>Spin Rust (WASM) + Dapr Sidecar</h1>
<div class="info">
<p>Runtime: Spin WebAssembly (Rust)</p>
<p>Dapr HTTP: <code>3500</code> (bridge 默认端口)</p>
<p>App ID: <code>spin-app</code></p>
<pre>
wsl curl -s http://localhost/spin-app/health
</pre>
</div>
</body>
</html>"#;
