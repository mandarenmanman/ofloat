---
inclusion: fileMatch
fileMatchPattern: "spin-app/**"
---

# Spin WASM HTTP 应用通用编码规范

本规范适用于 `spin-app/` 下所有语言的 Spin WASM HTTP 应用（方案一）。

## 架构模式

每个应用都是 HTTP server，由 Spin 托管为长驻进程，Dapr sidecar 通过 `-app-port` 双向通信。
业务代码只负责 HTTP 路由，所有基础设施操作通过 Dapr HTTP API 完成。

## 核心约束

- 绝不引入基础设施 SDK（redis、kafka、aws-sdk、数据库驱动等）
- 绝不硬编码云厂商依赖
- Dapr sidecar 地址定义为顶层常量：`http://127.0.0.1:3500`
- 所有对外请求通过 Dapr HTTP output binding 由 sidecar 出站，业务代码不直接访问外部网络
- WASM 内存有限，避免大量内存操作

## Dapr HTTP API 调用约定

通过标准 HTTP 客户端（各语言原生）调用 localhost Dapr sidecar：

| 操作 | 方法 | URL |
|---|---|---|
| 保存状态 | POST | `http://127.0.0.1:3500/v1.0/state/statestore` |
| 读取状态 | GET | `http://127.0.0.1:3500/v1.0/state/statestore/{key}` |
| 删除状态 | DELETE | `http://127.0.0.1:3500/v1.0/state/statestore/{key}` |
| 发布消息 | POST | `http://127.0.0.1:3500/v1.0/publish/pubsub/{topic}` |
| 服务调用 | ANY | `http://127.0.0.1:3500/v1.0/invoke/{app-id}/method/{path}` |
| HTTP Binding 出站 | POST | `http://127.0.0.1:3500/v1.0/bindings/{binding-name}` |
| 查询元数据 | GET | `http://127.0.0.1:3500/v1.0/metadata` |

## 必须实现的路由

每个应用至少包含以下端点：

- `GET /health` — 健康检查，返回 `{"status":"healthy"}`
- `GET /` — 首页，返回 HTML 展示应用信息

## spin.toml 通用配置

```toml
spin_manifest_version = 2

[application]
name = "spin-{lang}-app"
version = "0.1.0"

[[trigger.http]]
route = "/..."
component = "spin-{lang}-app"

[component.spin-{lang}-app]
source = "<编译产物路径>"
allowed_outbound_hosts = ["http://127.0.0.1:3500"]

[component.spin-{lang}-app.build]
command = "<构建命令>"
```

`allowed_outbound_hosts` 必须包含 Dapr sidecar 地址，否则 WASM 无法发起出站请求。

## 各语言要点

### Rust
- SDK: `spin-sdk` 5.2.0，使用 `#[http_component]` 宏
- HTTP 客户端: `spin_sdk::http::send`
- 编译目标: `wasm32-wasip1`，release 模式
- 构建命令: `cargo build --target wasm32-wasip1 --release`
- 产物路径: `target/wasm32-wasip1/release/<crate_name>.wasm`

### Go
- SDK: `spin-go-sdk` v2.2.1，使用 `spinhttp.Handle` 注册处理函数
- HTTP 客户端: `spinhttp.Send`（不能用标准库 `http.DefaultClient`）
- 编译器: TinyGo 0.35.0（要求 Go 1.19~1.23）
- 构建命令: `tinygo build -target=wasip1 -buildmode=c-shared -no-debug -o main.wasm .`
- 入口: `init()` 中注册 handler，`main()` 留空

### JavaScript
- 依赖: `itty-router` ^5.0.18, `@spinframework/build-tools` ^1.0.4, `@spinframework/wasi-http-proxy` ^1.0.0
- 路由: `AutoRouter` 链式写法，参数通过解构获取
- HTTP 客户端: 标准 `fetch` API
- 入口: `addEventListener('fetch', (event) => { event.respondWith(router.fetch(event.request)); })`
- 只用 ES module `import`，不用 `require()`
- 不用 Node.js 特有 API，只用标准 Web API

### TypeScript
- 与 JavaScript 相同的依赖和模式，额外需要 `tsconfig.json`
- 为函数参数和返回值添加类型注解
- 其余规则同 JavaScript

### Python
- SDK: `spin-sdk` 3.1.0, `componentize-py` 0.13.3
- 继承 `IncomingHandler`，实现 `handle_request` 方法
- HTTP 客户端: `spin_sdk.http.send`
- 构建命令: `componentize-py -w spin-http componentize app -o app.wasm`
- 响应体必须是 `bytes` 类型
