/// Dapr WASM Binding — Rust 实现
/// 编译: cargo build --target wasm32-wasip1 --release
///
/// 与 Go 版一致：直接调用 Dapr/wazero 当前实际提供的 wasi-http host imports：
/// - types
/// - streams
/// - default-outgoing-HTTP
///
/// 不再使用 `wasi-experimental-http` crate（其模块名与 Dapr 当前环境不匹配）。
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::io::{Read, Write};
use urlencoding::encode;

const DAPR_URL: &str = "http://127.0.0.1:3500";

mod wasi_http {
    pub type Handle = i32;

    #[link(wasm_import_module = "types")]
    extern "C" {
        #[link_name = "new-fields"]
        fn new_fields(fields_ptr: *const u8, fields_len: usize) -> Handle;
        #[link_name = "new-outgoing-request"]
        fn new_outgoing_request(
            method: Handle,
            method_ptr: *const u8,
            method_len: usize,
            path_ptr: *const u8,
            path_len: usize,
            query_ptr: *const u8,
            query_len: usize,
            scheme_is_some: usize,
            scheme: usize,
            scheme_ptr: *const u8,
            scheme_len: usize,
            authority_ptr: *const u8,
            authority_len: usize,
            headers: usize,
        ) -> Handle;
        #[link_name = "outgoing-request-write"]
        fn outgoing_request_write(request: Handle, stream_ptr: *mut u8);
        #[link_name = "future-incoming-response-get"]
        fn future_incoming_response_get(handle: Handle, ptr: *mut u8);
        #[link_name = "incoming-response-status"]
        fn incoming_response_status(handle: Handle) -> usize;
        #[link_name = "incoming-response-consume"]
        fn incoming_response_consume(handle: Handle, ptr: *mut u8);
    }

    #[link(wasm_import_module = "streams")]
    extern "C" {
        fn read(handle: Handle, len: i64, ptr: *mut u8);
        fn write(handle: Handle, ptr: *const u8, len: usize, result: *mut u8);
    }

    #[link(wasm_import_module = "default-outgoing-HTTP")]
    extern "C" {
        fn handle(
            request: Handle,
            a: usize,
            b: usize,
            c: usize,
            d: usize,
            e: usize,
            f: usize,
            g: usize,
        ) -> Handle;
    }

    #[derive(Debug)]
    pub struct HeaderValue {
        pub name: String,
        pub value: String,
    }

    #[derive(Debug)]
    pub struct HttpResponse {
        pub status_code: i32,
        pub body: String,
    }

    struct UrlParts {
        scheme_tag: u32,
        scheme_name: Option<String>,
        authority: String,
        path: String,
        query: String,
    }

    fn get_method(method: &str) -> Result<i32, String> {
        match method {
            "GET" => Ok(0),
            "HEAD" => Ok(1),
            "POST" => Ok(2),
            "PUT" => Ok(3),
            "DELETE" => Ok(4),
            "CONNECT" => Ok(5),
            "OPTIONS" => Ok(6),
            "TRACE" => Ok(7),
            "PATCH" => Ok(8),
            _ => Err(format!("unknown method: {method}")),
        }
    }

    fn parse_url(url: &str) -> Result<UrlParts, String> {
        let scheme_sep = url.find("//").ok_or_else(|| format!("invalid url: {url}"))?;
        let scheme_raw = url[..scheme_sep].trim_end_matches(':');
        let start = scheme_sep + 2;
        let after_host = url[start..]
            .find('/')
            .map(|i| start + i);

        let authority = match after_host {
            Some(ix) => url[start..ix].to_string(),
            None => url[start..].to_string(),
        };

        let (path, query) = match after_host {
            None => ("/".to_string(), String::new()),
            Some(ix) => {
                if let Some(qix_rel) = url[ix..].find('?') {
                    let qix = ix + qix_rel;
                    (url[ix..qix].to_string(), url[qix..].to_string())
                } else {
                    (url[ix..].to_string(), String::new())
                }
            }
        };

        let (scheme_tag, scheme_name) = match scheme_raw {
            "http" => (0, None),
            "https" => (1, None),
            other => (2, Some(other.to_string())),
        };

        Ok(UrlParts {
            scheme_tag,
            scheme_name,
            authority,
            path,
            query,
        })
    }

    fn header_handle(headers: &[HeaderValue]) -> Handle {
        if headers.is_empty() {
            unsafe { return new_fields(std::ptr::null(), 0) };
        }

        let mut bytes = Vec::with_capacity(headers.len() * 16);
        for h in headers {
            let name_ptr = h.name.as_ptr() as u32;
            let name_len = h.name.len() as u32;
            let value_ptr = h.value.as_ptr() as u32;
            let value_len = h.value.len() as u32;
            bytes.extend_from_slice(&name_ptr.to_le_bytes());
            bytes.extend_from_slice(&name_len.to_le_bytes());
            bytes.extend_from_slice(&value_ptr.to_le_bytes());
            bytes.extend_from_slice(&value_len.to_le_bytes());
        }

        unsafe { new_fields(bytes.as_ptr(), headers.len()) }
    }

    pub fn request(
        method: &str,
        url: &str,
        body: Option<&[u8]>,
        headers: &[HeaderValue],
    ) -> Result<HttpResponse, String> {
        let url = parse_url(url)?;
        let method_code = get_method(method)?;
        let header_handle = header_handle(headers);
        let scheme_ptr = url
            .scheme_name
            .as_ref()
            .map(|s| s.as_ptr())
            .unwrap_or(std::ptr::null());
        let scheme_len = url.scheme_name.as_ref().map(|s| s.len()).unwrap_or(0);

        let req = unsafe {
            new_outgoing_request(
                method_code,
                std::ptr::null(),
                0,
                url.path.as_ptr(),
                url.path.len(),
                url.query.as_ptr(),
                url.query.len(),
                1,
                url.scheme_tag as usize,
                scheme_ptr,
                scheme_len,
                url.authority.as_ptr(),
                url.authority.len(),
                header_handle as usize,
            )
        };

        let mut scratch = [0u8; 16];

        if let Some(body) = body.filter(|b| !b.is_empty()) {
            unsafe { outgoing_request_write(req, scratch.as_mut_ptr()) };
            let is_err = u32::from_le_bytes(scratch[0..4].try_into().unwrap());
            let output_stream = u32::from_le_bytes(scratch[4..8].try_into().unwrap()) as Handle;
            if is_err != 0 {
                return Err(format!("outgoing_request_write failed: {is_err}"));
            }
            unsafe { write(output_stream, body.as_ptr(), body.len(), scratch.as_mut_ptr()) };
            let write_is_err = u32::from_le_bytes(scratch[0..4].try_into().unwrap());
            if write_is_err != 0 {
                return Err(format!("streams.write failed: {write_is_err}"));
            }
        }

        let fut = unsafe { handle(req, 0, 0, 0, 0, 0, 0, 0) };
        let mut future_result = [0u8; 12];
        unsafe { future_incoming_response_get(fut, future_result.as_mut_ptr()) };
        let is_some = u32::from_le_bytes(future_result[0..4].try_into().unwrap());
        let is_err = u32::from_le_bytes(future_result[4..8].try_into().unwrap());
        let incoming = u32::from_le_bytes(future_result[8..12].try_into().unwrap()) as Handle;
        if is_some == 0 || is_err != 0 {
            return Err(format!("future_incoming_response_get failed: some={is_some} err={is_err}"));
        }

        let status = unsafe { incoming_response_status(incoming) } as i32;

        let mut consume_result = [0u8; 8];
        unsafe { incoming_response_consume(incoming, consume_result.as_mut_ptr()) };
        // Treat consume as a result-shaped value:
        // - first u32: is_err (0 = ok)
        // - second u32: input stream handle
        let consume_is_err = u32::from_le_bytes(consume_result[0..4].try_into().unwrap());
        let input_stream = u32::from_le_bytes(consume_result[4..8].try_into().unwrap()) as Handle;
        if consume_is_err != 0 {
            return Err(format!("incoming_response_consume failed: {consume_is_err}"));
        }

        let mut body_bytes = Vec::new();
        loop {
            let mut read_result = [0u8; 16];
            unsafe { read(input_stream, 64 * 1024, read_result.as_mut_ptr()) };
            let read_is_err = u32::from_le_bytes(read_result[0..4].try_into().unwrap());

            if read_is_err == 0 {
                let ptr = u32::from_le_bytes(read_result[4..8].try_into().unwrap()) as usize;
                let len = u32::from_le_bytes(read_result[8..12].try_into().unwrap()) as usize;
                if ptr == 0 || len == 0 {
                    break;
                }
                let bytes = unsafe { std::slice::from_raw_parts(ptr as *const u8, len) };
                body_bytes.extend_from_slice(bytes);
                continue;
            }

            // For result<list<u8>, stream-error>, the error payload starts at offset 4.
            // Tag 1 means `closed`, which is the normal end-of-stream signal.
            let stream_err_tag = u32::from_le_bytes(read_result[4..8].try_into().unwrap());
            if stream_err_tag == 1 {
                break;
            }
            return Err(format!("streams.read failed: {read_is_err}, tag={stream_err_tag}"));
        }

        let body = String::from_utf8_lossy(&body_bytes).to_string();

        Ok(HttpResponse {
            status_code: status,
            body,
        })
    }
}

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
    let data = serde_json::to_vec(&resp)
        .unwrap_or_else(|_| b"{\"status\":\"error\",\"action\":\"marshal\",\"error\":\"json encode failed\"}".to_vec());
    let _ = std::io::stdout().write_all(&data);
}

fn http_request(method: &str, url: &str, content_type: Option<&str>, body: Option<&[u8]>) -> Result<(i32, String), String> {
    let mut headers = Vec::new();
    if let Some(ct) = content_type {
        headers.push(wasi_http::HeaderValue {
            name: "Content-Type".into(),
            value: ct.into(),
        });
    }

    let resp = wasi_http::request(method, url, body, &headers)?;
    Ok((resp.status_code, resp.body))
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
    let payload = br#"{"operation":"get","metadata":{"path":"/kuaidihelp/smscallback"}}"#;
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
        Some(&body),
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
