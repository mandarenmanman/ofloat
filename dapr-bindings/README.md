# Dapr Bindings

本目录演示如何把 **WASM 模块** 作为 Dapr `bindings.wasm` 的执行目标运行，并通过 **Dapr + wazero** 提供的 host imports 实现：

- 外部 HTTP 调用
- Dapr state store 写入
- Dapr state store 读取

当前仓库里，**已验证可用**的语言只有：

- `go`
- `rust`

## 目录说明

- `go/`
  Go 版本，使用 TinyGo 编译，基于 `dev-wasm-go/http/client.WasiRoundTripper`
- `rust/`
  Rust 版本，直接对接 Dapr/wazero 当前实际提供的 wasi-http imports
- `dapr-bindings.nomad.hcl`
  Nomad job 模板
- `deploy.ps1`
  构建、上传 wasm 到 dufs、提交 Nomad job 的脚本

## 当前结论

### Go

Go 版是当前最稳定的实现。

特点：

- 使用 `TinyGo -target=wasi`
- 使用 `github.com/dev-wasm/dev-wasm-go/http/client`
- 通过 `WasiRoundTripper` 走 Dapr 提供的 wasi-http host ABI

### Rust

Rust 版已经打通，当前可用。

特点：

- 编译目标：`wasm32-wasip1`
- 不使用 `wasi-experimental-http` crate
- 直接调用以下 imports：
  - `types`
  - `streams`
  - `default-outgoing-HTTP`
- 显式导出 `cabi_realloc`，供 host 回填字符串 / list 结果

## 为什么不用 `wasi-experimental-http`

最开始 Rust 版尝试使用 `wasi-experimental-http` crate，但 Dapr 运行时报错：

```text
module[wasi_experimental_http] not instantiated
```

原因是 Dapr 当前这套运行环境并没有提供旧的：

```text
wasi_experimental_http
```

而是提供了更接近 Go 版所使用的这组 imports：

```text
types
streams
default-outgoing-HTTP
```

所以 Rust 最终改成了**直接手写 FFI 对接真实 imports**。

## Rust 打通过程中的关键坑

### 1. 旧 wasm 没被替换

如果 dufs 上始终用同一个文件名，例如：

```text
bindings.wasm
```

很容易出现 sidecar 仍然拿到旧产物的问题。

现在 `deploy.ps1` 每次部署都会生成新的文件名，例如：

```text
bindings-rust-20260306133012.wasm
```

同时还会更新 `config_version`，强制 Nomad 生成新 alloc。

### 2. Scheme 没显式传入

如果 Rust 调 `new-outgoing-request` 时不设置 scheme，host 可能默认按 HTTPS 处理，最终出现：

```text
Post "https://127.0.0.1:3500/...": http: server gave HTTP response to HTTPS client
```

现在 Rust 版会显式传：

- `http` -> tag `0`
- `https` -> tag `1`

### 3. 没有 `cabi_realloc`

如果 guest 没有导出 `cabi_realloc`，host 在把响应体写回 guest 内存时可能会崩掉。

Go/TinyGo 产物会自动带出：

- `memory`
- `cabi_realloc`

Rust 版需要手动导出：

```rust
#[no_mangle]
pub unsafe extern "C" fn cabi_realloc(...)
```

### 4. 响应体读取不是一次读完

HTTP body 读取不能假设一次 `streams.read` 就能把内容全拿到。

Rust 版最终做法是：

- 成功发请求
- `incoming-response-consume`
- 循环 `streams.read`
- 直到 stream closed

这样 `http-test` 才能从空 body 修正为真实返回值。

## 部署

现在 `deploy.ps1` 只支持：

- `go`
- `rust`

### 部署 Go

```powershell
.\dapr-bindings\deploy.ps1 go
```

### 部署 Rust

```powershell
.\dapr-bindings\deploy.ps1 rust
```

### 停止

```powershell
.\dapr-bindings\deploy.ps1 go stop
.\dapr-bindings\deploy.ps1 rust stop
```

## 调用方式

通过 Traefik / Dapr 调用 wasm binding：

```bash
curl -X POST http://localhost/dapr-bindings/v1.0/bindings/wasm \
  -H "Content-Type: application/json" \
  -H "dapr-app-id: dapr-bindings" \
  -d '{"operation":"execute","data":"{\"action\":\"health\"}"}'
```

## 已验证的 action

### health

```json
{"action":"health"}
```

### http-test

通过 Dapr output binding `external-http` 调用：

```json
{"action":"http-test"}
```

当前已验证返回：

```json
{"status":"ok","action":"http-test","result":{"body":"{\"msg\":\"success\",\"code\":1}","status":200}}
```

### save-state

```json
{"action":"save-state","data":{"key":"k1","value":"v1"}}
```

### get-state

```json
{"action":"get-state","data":{"key":"k1"}}
```

## 相关文件

- `go/main.go`
- `rust/src/main.rs`
- `deploy.ps1`
- `dapr-bindings.nomad.hcl`

