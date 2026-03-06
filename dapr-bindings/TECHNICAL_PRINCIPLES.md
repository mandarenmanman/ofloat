# Dapr WASM Binding Technical Principles

本文聚焦技术原理，说明在本项目里：

- WASM 模块是什么
- Dapr `bindings.wasm` 是怎么加载并执行 guest 的
- guest 和运行时（wazero / host imports）如何交互
- 为什么 Go / Rust 能跑，某些其他产物会失败
- 为什么 HTTP body 的读取、内存分配、ABI 对齐都很关键

---

## 1. 整体架构

在这个项目里，真正执行用户逻辑的不是普通二进制进程，而是一个 **WASM guest module**。

执行链路大致是：

1. 用户通过 HTTP 调用 Dapr output binding：
   - `POST /v1.0/bindings/wasm`
2. Dapr 的 `bindings.wasm` 组件收到请求
3. Dapr 读取配置里的 `url`
   - 从 dufs 下载 `.wasm`
4. Dapr 使用 **wazero** 实例化这个 `.wasm`
5. WASM 以 WASI 进程模型运行：
   - stdin 接收输入 JSON
   - stdout 输出结果 JSON
6. guest 内如果需要做 HTTP / state 调用：
   - 不能直接依赖普通 OS socket
   - 而是通过运行时提供的 **host imports** 调回宿主

所以，WASM guest 的本质是：

> 一个被 Dapr+wazero 托管执行的、通过 WASI 和 host imports 与外界交互的小进程。

---

## 2. guest / host 的角色

### guest

guest 就是我们自己编译出来的 `.wasm`，例如：

- `go/build/bindings.wasm`
- `rust/build/bindings-*.wasm`

它只知道：

- 自己的内存
- WASI 的 stdin / stdout
- 宿主暴露给它的 imports

它**不知道** Linux socket、Docker 网络、真实文件系统这些概念。

### host

host 就是执行这个 wasm 的环境，在这里主要包括：

- Dapr 的 `bindings.wasm`
- wazero runtime
- Dapr / wazero 注册进去的 WASI / wasi-http 相关 imports

host 的职责是：

- 实例化 guest module
- 提供 `wasi_snapshot_preview1` 的能力
- 提供 `types` / `streams` / `default-outgoing-HTTP` 这类 host functions
- 帮 guest 发真实 HTTP 请求
- 把结果写回 guest 内存

所以 guest 和 host 的关系可以理解成：

> guest 负责“描述我想做什么”，host 负责“替它实际完成外部世界交互”。

---

## 3. bindings.wasm 的调用模型

本项目里的 Dapr binding guest 采用的是一个非常简单的进程式协议：

### 输入

通过 stdin 传入 JSON，例如：

```json
{"action":"http-test"}
```

或者由 Dapr binding 包一层：

```json
{"operation":"execute","data":"{\"action\":\"http-test\"}"}
```

### 输出

guest 通过 stdout 输出 JSON，例如：

```json
{"status":"ok","action":"http-test","result":{"status":200,"body":"..."}}
```

也就是说：

- Dapr 并不是“直接调用 wasm 里的某个高层函数”
- 而是把 wasm 当成一个小型命令行进程来驱动

这也是为什么 Go / Rust / 其他语言的实现里，第一步都是：

- 读 stdin
- 解析 JSON
- dispatch action
- 写 stdout

---

## 4. 为什么 HTTP 不能直接用普通网络库

WASM guest 在这里并不直接拥有普通主机网络能力。

如果你在普通程序里写：

- Go：`net/http`
- Rust：`reqwest`
- JS：`fetch`

这些调用默认都假设：

- 进程自己有 socket
- 自己能 DNS 解析
- 自己能 TCP 连接

但在 Dapr `bindings.wasm` 的 guest 场景里，情况不是这样：

- guest 是一个沙箱内的 wasm 模块
- 真正能联网的是 host

因此 guest 不能依赖“常规 OS 网络接口”，而必须走：

> **wasi-http / host imports**

也就是说，guest 发 HTTP 的方式不是：

> 我自己创建 socket

而是：

> 我通过 ABI 告诉 host：请帮我发一个 HTTP 请求

---

## 5. 当前 Dapr 暴露的关键 imports

这次打通后，已经确认本项目里的 Dapr+wazero 对 guest 暴露的是这组核心 imports：

- `types`
- `streams`
- `default-outgoing-HTTP`
- 以及 `wasi_snapshot_preview1`

其中最重要的是：

### `types`

负责 HTTP 相关资源和元数据，例如：

- `new-fields`
- `new-outgoing-request`
- `outgoing-request-write`
- `future-incoming-response-get`
- `incoming-response-status`
- `incoming-response-consume`

这层主要是在表达：

- 请求方法
- headers
- scheme
- authority
- response handle

### `streams`

负责读写字节流，例如：

- `write`
- `read`

它不是 HTTP 专有的，而是更底层的 I/O 抽象。

### `default-outgoing-HTTP`

这里的：

- `handle`

可以理解成“真正触发 HTTP 请求发送”的入口。

也就是说，guest 先在 `types` 里构造 request，然后交给：

- `default-outgoing-HTTP/handle`

去真正执行。

---

## 6. 一个 HTTP 请求在 guest / host 之间如何流转

以 `http-test` 为例，请求链路大致如下：

### 第一步：构造 request

guest 先准备：

- method
- scheme
- authority
- path / query
- headers

例如：

- method = `POST`
- scheme = `http`
- authority = `127.0.0.1:3500`
- path = `/v1.0/bindings/external-http`

### 第二步：写 request body

如果是 POST，guest 还要把 body 写进 outgoing body stream。

例如：

```json
{"operation":"get","metadata":{"path":"/kuaidihelp/smscallback"}}
```

### 第三步：交给 host 执行

guest 调：

- `default-outgoing-HTTP/handle`

host 收到后，才会在真实环境里发出 HTTP 请求。

### 第四步：获取 future

HTTP 响应不会一定同步立刻完整返回，所以 guest 拿到的是一个：

- `future-incoming-response`

也就是“未来会有一个响应”。

### 第五步：取 response handle

guest 通过：

- `future-incoming-response-get`

拿到真正的 `incoming-response`。

然后可以读取：

- status
- headers
- body

### 第六步：消费 body

body 不是一整个字符串直接返回，而是一个 stream。

guest 需要：

1. consume response body
2. 获得 input stream
3. 循环 `streams.read`
4. 直到 stream closed

最终把所有 chunk 拼起来，得到完整 body。

---

## 7. 为什么 body 读取很容易出错

body 为空、崩溃、只读到一部分，通常都不是“接口没返回”，而是以下几个问题：

### 1. 把 `result` / `option` 的内存布局解错了

host 返回的很多东西不是简单的 `u32`，而是 canonical ABI 的：

- `option<T>`
- `result<T, E>`
- `list<u8>`

如果 guest 侧按错布局读取，就会出现：

- status 对，但 body 空
- handle = 0
- stream not found
- invalid memory address

### 2. 只读了一次 `streams.read`

response body 不保证一次返回完。

如果只读一次，就很可能：

- 读到 0 字节
- 读到部分内容

正确做法是循环读，直到 closed。

### 3. host 需要把结果写进 guest 内存

对于 `list<u8>` / `string` 这类返回值，host 需要在 guest 里分配内存。

这就依赖 guest 提供：

- `memory`
- `cabi_realloc`

如果缺这个能力，host 在写返回体时就可能直接崩。

---

## 8. 为什么 `cabi_realloc` 很重要

Rust 版这次一个关键修复就是补上：

```rust
#[no_mangle]
pub unsafe extern "C" fn cabi_realloc(...)
```

原因是：

- host 要把 `list<u8>` / `string` 等结果写回 guest
- 需要 guest 提供 canonical ABI 风格的重分配函数

Go/TinyGo 产物会自动带出这个导出。  
Rust 默认不会，所以需要手动提供。

如果没有它，常见现象就是：

- status 能拿到
- 一到 body 读取就炸
- 宿主栈里出现 `Malloc` / `streams.read` 相关 panic

---

## 9. 为什么 scheme 必须显式设置

Rust 版曾经出现过：

```text
Post "https://127.0.0.1:3500/v1.0/bindings/external-http": http: server gave HTTP response to HTTPS client
```

问题不是地址写错，而是：

- guest 没显式告诉 host scheme 是 `http`
- host 按默认逻辑把它当成了 `https`

而 Dapr sidecar 的 3500 端口是纯 HTTP。

所以：

- `scheme=http` 必须明确传给 host

否则就会出现：

- 明明访问的是 `127.0.0.1:3500`
- 实际却被构造成了 HTTPS 请求

---

## 10. 为什么 Go 容易，Rust 需要手写

### Go

Go 版之所以省事，是因为已经有：

- `dev-wasm-go/http/client.WasiRoundTripper`

它把：

- request 构造
- scheme / authority 处理
- body write
- future / stream 读取

都封装掉了。

所以业务代码看起来还能像普通 `net/http`。

### Rust

Rust 这边当前没有一套和 Dapr 当前 ABI **完全对齐、且已验证** 的现成封装。

所以最终只能：

- 手写 FFI
- 手写 canonical ABI 解包
- 手写 body stream 处理

这就是为什么：

- Go 版代码短很多
- Rust 版 `main.rs` 会更大

---

## 11. 为什么有些语言产物会失败

语言本身并不是核心问题，**产物形状**才是核心问题。

只要 guest 产物不满足当前 host 的 ABI 预期，就会失败。

典型失败方式包括：

### `env.abort`

有些 AssemblyScript 产物会导入：

- `env.abort`

但 Dapr 的 wazero 没提供 `env`，于是实例化阶段直接失败：

```text
module[env] not instantiated
```

### `wasi_experimental_http`

旧 crate 或旧实现可能会导入：

- `wasi_experimental_http`

但 Dapr 当前并没有提供这个模块，于是又会失败：

```text
module[wasi_experimental_http] not instantiated
```

### imports 名称风格不一致

例如：

- `new_outgoing_request`

和：

- `new-outgoing-request`

在 host 看来是两个完全不同的函数名。

哪怕只差一个连接符，也会失败。

---

## 12. 一句话理解这套系统

如果把这套机制抽象成一句话，可以这样理解：

> WASM guest 不直接联网、不直接持有系统资源，而是通过标准化 ABI 把“我要发 HTTP / 我要读 body / 我要返回字符串”的意图描述给 host；Dapr + wazero 作为 host 真正完成这些外部交互，并把结果按 canonical ABI 写回 guest 内存。

---

## 13. 适合记住的判断标准

以后只要判断某个语言能不能在这套体系里实现，可以先问这几个问题：

1. 能不能编成 **core wasm**？
2. 产物会不会带 host 不认识的 imports？
3. 能不能声明并调用：
   - `types`
   - `streams`
   - `default-outgoing-HTTP`
4. 能不能正确处理：
   - `option`
   - `result`
   - `list<u8>`
5. 是否需要导出：
   - `memory`
   - `cabi_realloc`
6. 能不能正确循环读 body stream？

这些都满足，理论上这门语言就能接入。

