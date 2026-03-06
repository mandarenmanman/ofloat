/// Dapr WASM Binding — Rust 实现
/// 编译: cargo build --target wasm32-wasip1 --release
///
/// 与 Go 版一致：通过 wasi_experimental_http host ABI 进行 HTTP 出站请求，
/// 供 Dapr wazero 运行时调用。
use bytes::Bytes;
use http::Request as HttpRequest;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::io::{Read, Write};
use urlencoding::encode;

const DAPR_URL: &str = "http://127.0.0.1:3500";

#[derive(Debug, Deserialize)]
struct Request {
    #[serde(default)]
    action: String,
    #[serde(default)]
    data: Value,
}

#[derive(Debug, Serialize)]
struct Response {
    status: String,
    action: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    result: Option<Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    error: Option<String>,
}

fn main() {
    let mut input = String::new();
    if let Err(e) = std::io::stdin().read_to_string(&mut input) {
        write_json(Response {
            status: "error".into(),
            action: "read".into(),
            result: None,
            error: Some(format!("read stdin failed: {e}")),
        });
        return;
    }

    if input.is_empty() {
        write_health();
        return;
    }

    let raw = if input.starts_with('"') {
        serde_json::from_str::<String>(&input).unwrap_or(input)
    } else {
        input
    };

    let req: Request = match serde_json::from_str(&raw) {
        Ok(v) => v,
        Err(_) => {
            write_json(Response {
                status: "ok".into(),
                action: "echo".into(),
                result: Some(json!({ "raw": raw })),
                error: None,
            });
            return;
        }
    };

    match req.action.as_str() {
        "" | "health" => write_health(),
        "echo" => write_json(Response {
            status: "ok".into(),
            action: "echo".into(),
            result: Some(req.data),
            error: None,
        }),
        "upper" => handle_upper(req.data),
        "http-test" => handle_http_test(),
        "save-state" => handle_save_state(req.data),
        "get-state" => handle_get_state(req.data),
        other => write_json(Response {
            status: "error".into(),
            action: other.into(),
            result: None,
            error: Some(format!("unknown action: {other}")),
        }),
    }
}

fn write_health() {
    write_json(Response {
        status: "healthy".into(),
        action: "health".into(),
        result: Some(json!({ "mode": "dapr-bindings-wasm-rust", "runtime": "wazero" })),
        error: None,
    });
}

fn write_json(resp: Response) {
    let data = serde_json::to_vec(&resp).unwrap_or_else(|_| b"{\"status\":\"error\",\"action\":\"marshal\",\"error\":\"json encode failed\"}".to_vec());
    let _ = std::io::stdout().write_all(&data);
}

fn http_request(method: &str, url: &str, content_type: Option<&str>, body: Option<Vec<u8>>) -> Result<(u16, String), String> {
    let mut builder = HttpRequest::builder().method(method).uri(url);
    if let Some(ct) = content_type {
        builder = builder.header("Content-Type", ct);
    }

    let req = builder
        .body(body.map(Bytes::from))
        .map_err(|e| format!("build request failed: {e}"))?;

    let mut resp = wasi_experimental_http::request(req).map_err(|e| format!("request failed: {e}"))?;
    let status = resp.status_code.as_u16();
    let body = String::from_utf8(resp.body_read_all().map_err(|e| format!("read body failed: {e}"))?)
        .map_err(|e| format!("utf8 decode failed: {e}"))?;
    Ok((status, body))
}

fn handle_upper(data: Value) {
    let Some(s) = data.as_str() else {
        write_json(Response {
            status: "error".into(),
            action: "upper".into(),
            result: None,
            error: Some("missing data".into()),
        });
        return;
    };

    write_json(Response {
        status: "ok".into(),
        action: "upper".into(),
        result: Some(json!({ "data": s.to_uppercase() })),
        error: None,
    });
}

fn handle_http_test() {
    let payload = br#"{"operation":"get","metadata":{"path":"/kuaidihelp/smscallback"}}"#.to_vec();
    match http_request(
        "POST",
        &format!("{DAPR_URL}/v1.0/bindings/external-http"),
        Some("application/json"),
        Some(payload),
    ) {
        Ok((status, body)) => write_json(Response {
            status: "ok".into(),
            action: "http-test".into(),
            result: Some(json!({ "status": status, "body": body })),
            error: None,
        }),
        Err(e) => write_json(Response {
            status: "error".into(),
            action: "http-test".into(),
            result: None,
            error: Some(e),
        }),
    }
}

fn handle_save_state(data: Value) {
    let items = match data {
        Value::Array(arr) => Value::Array(arr),
        Value::Object(mut map) => {
            if !map.contains_key("key") {
                write_json(Response {
                    status: "error".into(),
                    action: "save-state".into(),
                    result: None,
                    error: Some("data must have key".into()),
                });
                return;
            }
            if !map.contains_key("value") {
                map.insert("value".into(), Value::Null);
            }
            Value::Array(vec![Value::Object(map)])
        }
        _ => {
            write_json(Response {
                status: "error".into(),
                action: "save-state".into(),
                result: None,
                error: Some("missing data".into()),
            });
            return;
        }
    };

    let body = match serde_json::to_vec(&items) {
        Ok(v) => v,
        Err(e) => {
            write_json(Response {
                status: "error".into(),
                action: "save-state".into(),
                result: None,
                error: Some(format!("encode body failed: {e}")),
            });
            return;
        }
    };

    match http_request(
        "POST",
        &format!("{DAPR_URL}/v1.0/state/statestore"),
        Some("application/json"),
        Some(body),
    ) {
        Ok((status, body)) if status >= 400 => write_json(Response {
            status: "error".into(),
            action: "save-state".into(),
            result: Some(json!({ "status": status })),
            error: Some(body),
        }),
        Ok((status, body)) => {
            let keys = items.as_array().map(|a| a.len()).unwrap_or(0);
            write_json(Response {
                status: "ok".into(),
                action: "save-state".into(),
                result: Some(json!({ "keys": keys, "status": status, "body": body })),
                error: None,
            })
        }
        Err(e) => write_json(Response {
            status: "error".into(),
            action: "save-state".into(),
            result: None,
            error: Some(e),
        }),
    }
}

fn handle_get_state(data: Value) {
    let key = match data.get("key").and_then(Value::as_str) {
        Some(k) if !k.is_empty() => k,
        _ => {
            write_json(Response {
                status: "error".into(),
                action: "get-state".into(),
                result: None,
                error: Some("data must be {\"key\":\"...\"}".into()),
            });
            return;
        }
    };

    let url = format!("{DAPR_URL}/v1.0/state/statestore/{}", encode(key));
    match http_request("GET", &url, None, None) {
        Ok((404, _)) => write_json(Response {
            status: "ok".into(),
            action: "get-state".into(),
            result: Some(json!({ "key": key, "value": Value::Null, "found": false })),
            error: None,
        }),
        Ok((status, body)) if status >= 400 => write_json(Response {
            status: "error".into(),
            action: "get-state".into(),
            result: Some(json!({ "status": status })),
            error: Some(body),
        }),
        Ok((_, body)) => write_json(Response {
            status: "ok".into(),
            action: "get-state".into(),
            result: Some(json!({ "key": key, "value": body, "found": true })),
            error: None,
        }),
        Err(e) => write_json(Response {
            status: "error".into(),
            action: "get-state".into(),
            result: None,
            error: Some(e),
        }),
    }
}
