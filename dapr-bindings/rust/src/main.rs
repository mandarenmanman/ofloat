/// Dapr WASM Binding — Rust 实现
/// 编译: cargo build --target wasm32-wasip1 --release
///
/// stdin/stdout JSON 协议，与 Go 版本行为一致
use serde::{Deserialize, Serialize};
use std::io::Read;

const _DAPR_URL: &str = "http://127.0.0.1:3500";

#[derive(Deserialize)]
struct Request {
    action: Option<String>,
    data: Option<serde_json::Value>,
}

#[derive(Serialize)]
struct Response {
    status: String,
    action: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    result: Option<serde_json::Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    error: Option<String>,
}

fn write_response(resp: &Response) {
    print!("{}", serde_json::to_string(resp).unwrap());
}

fn main() {
    let mut input = String::new();
    if std::io::stdin().read_to_string(&mut input).is_err() {
        write_response(&Response {
            status: "error".into(),
            action: "".into(),
            result: None,
            error: Some("read stdin failed".into()),
        });
        return;
    }

    // 空输入 = 健康检查
    if input.trim().is_empty() {
        write_response(&Response {
            status: "healthy".into(),
            action: "health".into(),
            result: Some(serde_json::json!({"mode": "dapr-bindings-wasm-rust"})),
            error: None,
        });
        return;
    }

    let req: Request = match serde_json::from_str(&input) {
        Ok(r) => r,
        Err(_) => {
            write_response(&Response {
                status: "ok".into(),
                action: "echo".into(),
                result: Some(serde_json::json!({"raw": input})),
                error: None,
            });
            return;
        }
    };

    let action = req.action.as_deref().unwrap_or("");
    match action {
        "health" => write_response(&Response {
            status: "healthy".into(),
            action: "health".into(),
            result: Some(serde_json::json!({"mode": "dapr-bindings-wasm-rust"})),
            error: None,
        }),
        "echo" => write_response(&Response {
            status: "ok".into(),
            action: "echo".into(),
            result: Some(serde_json::json!({"data": req.data})),
            error: None,
        }),
        "http-test" => write_response(&Response {
            status: "error".into(),
            action: "http-test".into(),
            result: None,
            error: Some("HTTP client not available in Rust WASM build".into()),
        }),
        "save-state" => write_response(&Response {
            status: "error".into(),
            action: "save-state".into(),
            result: None,
            error: Some("HTTP client not available in Rust WASM build".into()),
        }),
        "get-state" => write_response(&Response {
            status: "error".into(),
            action: "get-state".into(),
            result: None,
            error: Some("HTTP client not available in Rust WASM build".into()),
        }),
        "upper" => {
            let s = req.data
                .as_ref()
                .and_then(|v| v.as_str())
                .unwrap_or("");
            write_response(&Response {
                status: "ok".into(),
                action: "upper".into(),
                result: Some(serde_json::json!({"data": s.to_uppercase()})),
                error: None,
            });
        }
        _ => write_response(&Response {
            status: "error".into(),
            action: action.into(),
            result: None,
            error: Some(format!("unknown action: {}", action)),
        }),
    }
}
