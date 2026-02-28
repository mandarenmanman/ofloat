---
inclusion: fileMatch
fileMatchPattern: "**/*.rs"
---

# Spin Rust WASM 编码规范

## 依赖

只允许以下依赖，不要添加任何基础设施相关的 crate：

```toml
[dependencies]
anyhow = "1"
spin-sdk = "5.2.0"
serde = { version = "1", features = ["derive"] }       # 按需
serde_json = "1"                                        # 按需
```

## 代码模板

```rust
use spin_sdk::http::{IntoResponse, Request, Response};
use spin_sdk::http_component;

#[http_component]
fn handle_request(req: Request) -> anyhow::Result<impl IntoResponse> {
    let path = req.path();
    let method = req.method().as_str();

    match (method, path) {
        ("GET", "/health") => Ok(Response::builder()
            .status(200)
            .header("content-type", "application/json")
            .body(r#"{"status":"healthy"}"#)
            .build()),

        // 更多路由...

        _ => Ok(Response::builder()
            .status(404)
            .body("Not Found")
            .build()),
    }
}
```

## 调用 Dapr 的方式

使用 `spin_sdk::http::send` 发出站请求：

```rust
use spin_sdk::http::{Method, Request as OutboundRequest, send};

// 保存状态
let dapr_req = OutboundRequest::builder()
    .method(Method::Post)
    .uri("http://127.0.0.1:3500/v1.0/state/statestore")
    .header("content-type", "application/json")
    .body(r#"[{"key":"order-1","value":{"item":"book","qty":2}}]"#)
    .build();
let resp = send(dapr_req).await?;

// 读取状态
let dapr_req = OutboundRequest::builder()
    .method(Method::Get)
    .uri("http://127.0.0.1:3500/v1.0/state/statestore/order-1")
    .build();
let resp = send(dapr_req).await?;

// 发布消息
let dapr_req = OutboundRequest::builder()
    .method(Method::Post)
    .uri("http://127.0.0.1:3500/v1.0/publish/pubsub/orders")
    .header("content-type", "application/json")
    .body(r#"{"orderId":"123","item":"book"}"#)
    .build();
let resp = send(dapr_req).await?;
```

## 注意事项

- Dapr sidecar 地址定义为常量：`const DAPR_URL: &str = "http://127.0.0.1:3500";`
- `spin.toml` 的 `allowed_outbound_hosts` 必须包含 Dapr 地址
- 不要使用 `std::net`、`tokio`、`reqwest` 等，Spin WASM 环境不支持
- 不要使用 `async fn handle_request`，Spin 的 `#[http_component]` 宏自行处理异步
- 编译目标是 `wasm32-wasip1`，注意兼容性
