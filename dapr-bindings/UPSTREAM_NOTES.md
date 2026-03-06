# Rust WASM Upstream Notes

本文记录 `dapr-bindings/rust` 这次在 **Dapr + wazero** 环境下打通 WASM HTTP / state 调用的过程，以及是否有必要把这份实现合并到：

- `github.com/dapr/components-contrib/tree/main/common/wasm`

## 结论

当前阶段，**不建议直接把这份 Rust 实现原样合并到上游**。

原因不是 Rust 方案不可行，而是：

1. 它已经证明 **Rust 可以在 Dapr + wazero 下跑通**
2. 但当前代码更适合作为 **项目内验证通过的参考实现**
3. 还不够适合作为 `components-contrib/common/wasm` 里的官方公共样例

换句话说：

- **技术上可行**
- **工程上暂不建议直接 upstream**

## 当前已验证的能力

Rust 版目前已经在本项目里验证通过：

- `health`
- `http-test`
- `save-state`
- `get-state`

其中 `http-test` 已经拿到真实外部接口响应：

```json
{"status":"ok","action":"http-test","result":{"body":"{\"msg\":\"success\",\"code\":1}","status":200}}
```

这说明：

- Rust guest 可以被 Dapr `bindings.wasm` 正常实例化
- 可以通过 Dapr / wazero 提供的 host imports 发起 HTTP
- 可以正确读取响应体

## 为什么最初的 Rust 方案不行

最开始 Rust 尝试使用：

- `wasi-experimental-http`

但在 Dapr 中运行时报错：

```text
module[wasi_experimental_http] not instantiated
```

说明 Dapr 当前并没有暴露旧的：

```text
wasi_experimental_http
```

而是暴露了更接近 Go 版使用的 imports：

- `types`
- `streams`
- `default-outgoing-HTTP`

所以 Rust 最终方案不是沿用现成 crate，而是**直接手写 FFI 对接 Dapr 当前真实 ABI**。

## Rust 最终采用的实现方式

### 1. 直接声明 host imports

Rust 版不再依赖 `wasi-experimental-http` crate，而是直接声明：

- `types/new-fields`
- `types/new-outgoing-request`
- `types/outgoing-request-write`
- `types/future-incoming-response-get`
- `types/incoming-response-status`
- `types/incoming-response-consume`
- `streams/read`
- `streams/write`
- `default-outgoing-HTTP/handle`

### 2. 显式传入 scheme

如果不给 `new-outgoing-request` 设置 scheme，host 可能默认按 HTTPS 处理，
从而出现：

```text
http: server gave HTTP response to HTTPS client
```

Rust 版最终修正为：

- `http` -> tag `0`
- `https` -> tag `1`
- `other` -> tag `2` + 字符串

### 3. 导出 `cabi_realloc`

Rust 版最开始只有：

- `memory`
- `_start`

没有：

- `cabi_realloc`

而 host 在把 `list<u8>` / `string` 结果写回 guest 内存时，需要使用 canonical ABI allocator。

Go/TinyGo 版会自动导出这个符号，Rust 版则需要手动提供：

```rust
#[no_mangle]
pub unsafe extern "C" fn cabi_realloc(...) -> *mut u8
```

### 4. body 不能只读一次

一开始 Rust 虽然能拿到 `200`，但 body 为空。

原因是：

- response stream 不能假设一次 `read` 就读完
- 必须按流式协议循环读取，直到 stream `closed`

因此最终 Rust 版：

1. 获取 `incoming-response`
2. consume body
3. 循环 `streams.read`
4. 累积所有 chunk
5. 遇到 closed 正常结束

## 为什么现在不建议直接 upstream

### 1. 当前代码是“打通实现”，不是“公共样板”

当前 Rust 版的目标是：

- 验证 Dapr 当前 ABI 能否在 Rust 下跑通

它已经完成了这个目标，但它仍然带有较强的“ABI 对齐痕迹”：

- 手写 imports
- 手写内存布局处理
- 手写 body stream 解包

这类代码在项目内很有价值，但放进上游公共目录时，维护要求会提高很多。

### 2. 上游一旦接收，就意味着需要长期维护

如果把 Rust 版放进 `components-contrib/common/wasm`，上游使用者会默认认为：

- 这是 Dapr 官方认可的 Rust guest 参考
- 后续 ABI 变化时，这份代码应继续可用

这意味着维护责任包括：

- Dapr ABI 变更跟进
- wazero 行为变化跟进
- Rust 目标与编译器升级兼容性
- 示例代码测试与文档同步

### 3. 当前文件仍然偏大、偏“调通优先”

`rust/src/main.rs` 目前已经比较长，包含：

- ABI 层
- URL 拆解
- Header 构造
- Body 写入
- Future / stream 读取
- 业务 action

从上游可维护性的角度，更适合先拆成更清晰的结构，而不是直接原样提交。

## 如果以后要 upstream，建议先做什么

如果后续确实希望提 PR 到 `components-contrib/common/wasm`，建议先把当前实现整理成更适合上游接收的形态。

### 建议的整理步骤

1. 把 ABI 层独立成单独模块
   - 如 `ffi.rs`
   - 明确标注每个 import 的来源与用途

2. 把 HTTP 客户端逻辑独立成单独模块
   - 如 `http_client.rs`
   - 对外只暴露 `request()` 或更小的 API

3. 保留最小 action 集
   - `health`
   - `http-test`
   - 可选：`save-state`
   - 可选：`get-state`

4. 增加说明文档
   - 为什么不能直接用 `wasi-experimental-http`
   - 为什么需要 `cabi_realloc`
   - 为什么要显式设置 scheme
   - 为什么 body 必须循环读

5. 增加最小验证脚本或测试说明
   - 构建方式
   - imports 检查方式
   - 在 Dapr 环境里的验证方法

### 更合适的 upstream 目标

与其一开始就把完整业务版放进上游，更合适的方式可能是：

1. 先提交一个 **Rust 最小可运行样例**
2. 或者提交一份 **Rust guest ABI 对接说明**
3. 再逐步补充 state / binding / external HTTP 示例

## 当前建议

当前更合理的定位是：

- 把 `rust/` 保留在本仓库中
- 作为 **已验证可用的 Rust 参考实现**
- 后续如果需要，再提炼成一个更小、更干净、更适合维护的 upstream 版本

## 一句话总结

当前 Rust 版已经证明：

> **Rust 按照 Dapr + wazero 当前实际暴露的 ABI，可以实现与 Go 版等价的 WASM binding guest。**

但是否要直接合并到上游，答案是：

> **现在不急着合并；先保留为本仓库参考实现，等代码结构和维护边界更清晰后再考虑 upstream。**

