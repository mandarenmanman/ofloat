---
inclusion: fileMatch
fileMatchPattern: "dapr-bindings/**"
---

# Dapr WASM Binding 通用编码规范

本规范适用于 `dapr-bindings/` 下所有语言的 Dapr WASM Binding 应用（方案二）。

## 架构模式

不使用 Spin，业务代码编译为标准 `wasip1` WASM，由 Dapr 的 `bindings.wasm` component 按需加载执行。

调用链路：`客户端 → Traefik → Dapr sidecar → /v1.0/bindings/wasm → WASM (stdin→stdout)`
经 Traefik 调用时必须带 HTTP 头 `dapr-app-id: dapr-bindings`，否则 Dapr 返回 `ERR_DIRECT_INVOKE`。

## 核心约束

- 业务代码是 stdin/stdout CLI 程序，不是 HTTP server
- 没有 Spin 参与，Nomad Job 只有一个 task：`dapr-sidecar`
- 不支持 service invocation，只能通过 `/v1.0/bindings/wasm` API 调用
- 绝不引入基础设施 SDK（redis、kafka、aws-sdk 等）
- WASM 产物上传到 dufs 文件服务器（非 OCI registry）

## 通用协议

所有语言实现相同的 stdin/stdout JSON 协议：

输入（stdin）：
```json
{"action":"<action-name>","data":<any>}
```

输出（stdout）：
```json
{"status":"ok|error|healthy","action":"<action-name>","result":<any>,"error":"<msg>"}
```

空输入 = 健康检查，返回 `{"status":"healthy","action":"health"}`。

必须实现的 action：
- `health` — 健康检查
- `echo` — 回显 data 字段

## wasi-http 出站请求

WASM 内不能直接跑 TCP，需通过 host 提供的 wasi-http 接口发请求。Dapr 的 wazero 运行时实现了这套 host ABI，所以能访问 sidecar。

需要出站 HTTP 的 action（`http-test`、`save-state`、`get-state`）都依赖 wasi-http。

## Dapr HTTP API 调用约定

通过 wasi-http 调用 localhost Dapr sidecar：

| 操作 | 方法 | URL |
|---|---|---|
| 保存状态 | POST | `http://127.0.0.1:3500/v1.0/state/statestore` |
| 读取状态 | GET | `http://127.0.0.1:3500/v1.0/state/statestore/{key}` |
| 删除状态 | DELETE | `http://127.0.0.1:3500/v1.0/state/statestore/{key}` |
| 发布消息 | POST | `http://127.0.0.1:3500/v1.0/publish/pubsub/{topic}` |
| HTTP Binding 出站 | POST | `http://127.0.0.1:3500/v1.0/bindings/{binding-name}` |

## 外部调用方式

通过 Dapr bindings API 调用，请求体格式固定：

```json
{
  "operation": "execute",
  "data": "{\"action\":\"health\"}"
}
```

注意 `data` 字段是 JSON 字符串（需要转义），不是嵌套对象。

## 各语言要点

### Go
- 编译器: 标准 Go（非 TinyGo），go1.23.6
- 编译命令: `GOOS=wasip1 GOARCH=wasm go build -o build/bindings.wasm .`
- wasi-http: `github.com/dev-wasm/dev-wasm-go/http`，使用 `WasiRoundTripper` 适配 `net/http`
- 入口: `func main()` 读 `os.Stdin`，写 `os.Stdout`
- JSON: 标准库 `encoding/json`

```go
import wasiclient "github.com/dev-wasm/dev-wasm-go/http/client"

client := &http.Client{Transport: wasiclient.WasiRoundTripper{}}
resp, err := client.Get("http://127.0.0.1:3500/v1.0/state/statestore/" + key)
```

### Rust
- 编译目标: `wasm32-wasip1`，release 模式
- 编译命令: `cargo build --target wasm32-wasip1 --release`
- wasi-http: 手动声明 FFI 绑定（`types`、`streams`、`default-outgoing-HTTP` 三个 wasm import module），直接调用 Dapr/wazero 提供的 host ABI
- 必须导出 `cabi_realloc`，供 host 在 guest 内存中放置返回数据
- 依赖: `serde` + `serde_json`（序列化）、`urlencoding`（URL 编码）
- 入口: `fn main()` 读 `std::io::stdin`，写 `std::io::stdout`

```rust
// wasi-http FFI 模块结构
mod wasi_http {
    // #[link(wasm_import_module = "types")] — 请求/响应/header 操作
    // #[link(wasm_import_module = "streams")] — 读写流
    // #[link(wasm_import_module = "default-outgoing-HTTP")] — 发起请求
    pub fn request(method, url, body, headers) -> Result<HttpResponse, String>;
}
```

## Nomad Job 要点

- 只有一个 task：`dapr-sidecar`（Docker driver）
- 没有 `spin-webhost` task，没有 `-app-port` 参数
- 必须配置 `bindings.wasm` component，`url` 指向 dufs 上的 WASM 文件
- dufs 地址通过 Consul 服务发现：`{{ range service "dufs" }}{{ .Address }}:{{ .Port }}{{ end }}`
- 内存配置：`memory = 256`，`memory_max = 512`

## 测试验证

```bash
# 通过 Traefik（必须带 dapr-app-id 头）
wsl curl -s -X POST http://localhost/dapr-bindings/v1.0/bindings/wasm \
  -H "Content-Type: application/json" \
  -H "dapr-app-id: dapr-bindings" \
  -d '{"operation":"execute","data":"{\"action\":\"health\"}"}'
```
