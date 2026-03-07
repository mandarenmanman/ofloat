# 🧠 ofloat

![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)
![WASM](https://img.shields.io/badge/WebAssembly-Enabled-orange)
![Dapr](https://img.shields.io/badge/Dapr-v1.16.9-blue)
![Spin](https://img.shields.io/badge/Fermyon_Spin-v3.6.2-lightgrey)

> AI 只写业务逻辑，基础设施的事全部消失。从 Prompt 到生产部署，端到端零摩擦。

---

## 核心思路

让 AI（或开发者）只写纯粹的 HTTP handler / CLI 逻辑，所有基础设施操作 = 向 Dapr sidecar 发 HTTP 请求。不引入任何 Redis SDK、Kafka client、云厂商依赖。

```
┌─────────────────────────────────────────────────────────┐
│                    你（或 AI）只需要写这一层              │
│                                                         │
│   fn handle_request(req) -> Response {                  │
│       // 纯粹的 HTTP 数据处理                            │
│       // 向 localhost:3500 发 HTTP 请求 = 操作任何基础设施 │
│   }                                                     │
├─────────────────────────────────────────────────────────┤
│  Spin (WASM 沙箱)    │  Dapr (基础设施抽象)              │
│  微秒级冷启动          │  Redis/Kafka/DynamoDB 全透明     │
│  几百 KB 内存          │  换后端只改 YAML，代码零修改       │
├─────────────────────────────────────────────────────────┤
│  Nomad (编排) + Consul (服务发现) + Traefik (反向代理)   │
└─────────────────────────────────────────────────────────┘
```

---

## 工具链版本

| 工具 | 版本 | 备注 |
|---|---|---|
| Spin CLI | v3.6.2 | Windows amd64 |
| Dapr (daprd) | 1.16.9 | Docker 镜像 `daprio/daprd:1.16.9` |
| Nomad | v1.11.2 | 远程服务器运行 |
| Consul | 1.22.0 | 远程服务器运行，服务发现（1.22.4+ UI 有已知 bug） |
| Traefik | v3.4 | Docker 镜像 `localhost:15000/traefik:v3.4` |
| Rust spin-sdk | 5.2.0 | |
| Go spin-go-sdk | v2.2.1 | TinyGo 0.35.0 编译 |
| JS/TS @spinframework | build-tools 1.0.4 / wasi-http-proxy 1.0.0 | itty-router 5.0.18 |
| Python spin-sdk | 3.1.0 | componentize-py 0.13.3 |
| Node.js | v22.17.0 | 构建 JS/TS 用 |
| dufs | v0.45.0 | 文件服务器，方案二 WASM 产物分发 |
| Just | latest | Monorepo 命令编排 |

---

## 两种架构模式

### 方案一：Spin WASM HTTP 应用（主流模式）

业务代码是 HTTP server，由 Spin 托管为长驻进程，Dapr sidecar 通过 `-app-port 80` 双向通信。

```
外部请求 → Traefik (:80) → Dapr sidecar (:3500) → Spin WASM (:80)
                                    ↕
                              Redis / Consul / ...
```

Nomad Job 包含两个 task：
- `spin-webhost`（raw_exec）：从 OCI registry 拉取 WASM，监听 `:80`
- `dapr-sidecar`（docker）：Dapr 进程，连接 Spin `:80`，暴露 Dapr HTTP `:3500`

支持语言：Rust / Go / JavaScript / TypeScript / Python

### 方案二：Dapr WASM Binding（无 HTTP server）

业务代码是 stdin/stdout CLI 程序，编译为 `wasip1` WASM，由 Dapr 的 `bindings.wasm` component 按需加载执行。没有 Spin 参与。

```
外部请求 → Traefik (:80) → Dapr sidecar (:3500) → /v1.0/bindings/wasm → WASM (stdin→stdout)
                                    ↕
                              Redis / Consul / ...
```

Nomad Job 只有一个 task：`dapr-sidecar`（无 `-app-port`）。WASM 产物上传到 dufs 文件服务器。

支持语言：Go / Rust（Go 已完整实现 wasi-http 出站）

---

## 内部调用：业务代码 → Dapr Sidecar

所有语言的业务代码通过 HTTP 请求与同 Pod 的 Dapr sidecar 交互，地址固定为 `http://127.0.0.1:3500`：

| 操作 | 方法 | URL |
|---|---|---|
| 保存状态 | POST | `/v1.0/state/statestore` |
| 读取状态 | GET | `/v1.0/state/statestore/{key}` |
| 删除状态 | DELETE | `/v1.0/state/statestore/{key}` |
| 发布消息 | POST | `/v1.0/publish/pubsub/{topic}` |
| 服务调用 | ANY | `/v1.0/invoke/{app-id}/method/{path}` |
| HTTP Binding 出站 | POST | `/v1.0/bindings/{binding-name}` |

### 外部 HTTP 出站

Spin 在 bridge 网络模式下无法直接访问外部网络，需通过 Dapr HTTP output binding 由 sidecar 代理出站：

```javascript
// JS 示例：通过 Dapr HTTP binding 调用外部 API
const resp = await fetch('http://127.0.0.1:3500/v1.0/bindings/external-http', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ operation: 'get', metadata: { path: '/api/endpoint' } }),
});
```

当前配置了两个 HTTP output binding：
- `consul-http` → Consul API (`http://192.168.3.63:8500`)
- `external-http` → 外部 API (`http://api.24box.cn:9002`)


---

## 外部调用：客户端 → 应用

### 方案一（Spin 应用）

通过 Traefik 反向代理，基于 Consul Catalog 自动路由。每个应用注册 Consul 服务时带 Traefik tag，路由规则为 `PathPrefix(/{app-name})`，自动 strip prefix 后转发到 Dapr sidecar。

```bash
# 健康检查（经 Traefik → Dapr → Spin）
wsl curl -s http://localhost/spin-go-app/health
# → {"status":"healthy"}

# 保存状态
wsl curl -s -X POST http://localhost/spin-rust-app/state \
  -H "Content-Type: application/json" \
  -d '[{"key":"k1","value":"hello"}]'

# 读取状态
wsl curl -s http://localhost/spin-js-app/state/k1

# 服务间调用（经 Dapr service invocation）
wsl curl -s http://localhost/spin-ts-app/consul/nodes
```

也可以直接通过 Dapr sidecar 端口调用（需知道映射端口）：

```bash
wsl curl -s http://localhost:{dapr-port}/v1.0/invoke/spin-go-app/method/health
```

### 方案二（Binding 应用）

通过 Traefik 路由到 Dapr sidecar，调用 `/v1.0/bindings/wasm` 接口。**必须**带 `dapr-app-id` 头：

```bash
# 健康检查
wsl curl -s -X POST http://localhost/dapr-bindings/v1.0/bindings/wasm \
  -H "Content-Type: application/json" \
  -H "dapr-app-id: dapr-bindings" \
  -d '{"operation":"execute","data":"{\"action\":\"health\"}"}'

# 保存状态
wsl curl -s -X POST http://localhost/dapr-bindings/v1.0/bindings/wasm \
  -H "Content-Type: application/json" \
  -H "dapr-app-id: dapr-bindings" \
  -d '{"operation":"execute","data":"{\"action\":\"save-state\",\"data\":{\"key\":\"k1\",\"value\":\"v1\"}}"}'
```

> ⚠️ 所有测试请求必须通过 `wsl curl` 执行，不要用 Windows 的 `curl.exe` 或 `Invoke-WebRequest`。服务运行在远程服务器的网络命名空间内。

---

## 项目结构

```
.
├── spin-app/                         # 方案一：Spin WASM HTTP 应用
│   ├── spin-app.nomad.hcl            # 统一 Nomad Job 模板（<<APP_NAME>> 占位符）
│   ├── deploy.ps1                    # 统一部署脚本: .\deploy.ps1 <go|rust|js|ts|python>
│   ├── rust/                         # Rust 应用 (spin-sdk 5.2.0)
│   │   ├── src/lib.rs
│   │   ├── Cargo.toml
│   │   └── spin.toml                 # app-name: spin-app
│   ├── go/                           # Go 应用 (spin-go-sdk v2.2.1 + TinyGo)
│   │   ├── main.go
│   │   ├── go.mod
│   │   └── spin.toml                 # app-name: spin-go-app
│   ├── js/                           # JavaScript 应用 (itty-router)
│   │   ├── src/index.js
│   │   ├── package.json
│   │   └── spin.toml                 # app-name: spin-js-app
│   ├── ts/                           # TypeScript 应用
│   │   ├── src/index.ts
│   │   ├── package.json
│   │   └── spin.toml                 # app-name: spin-ts-app
│   └── python/                       # Python 应用 (componentize-py)
│       ├── app.py
│       ├── requirements.txt
│       └── spin.toml                 # app-name: spin-python-app
│
├── dapr-bindings/                    # 方案二：Dapr WASM Binding 应用
│   ├── dapr-bindings.nomad.hcl       # 统一 Nomad Job 模板
│   ├── deploy.ps1                    # 统一部署脚本: .\deploy.ps1 <go|rust>
│   ├── go/                           # Go 实现（wasi-http 出站已实现）
│   │   ├── main.go
│   │   ├── go.mod
│   │   └── build.sh
│   └── rust/                         # Rust 实现
│       ├── src/main.rs
│       └── Cargo.toml
│
├── IaC/                              # 基础设施即代码
│   ├── consul/                       # Consul 配置与安装脚本
│   ├── dapr/                         # 自定义 daprd Docker 镜像
│   ├── nomad/                        # Nomad 配置 + 基础设施 Job
│   │   ├── redis.nomad.hcl
│   │   ├── dapr-placement.nomad.hcl
│   │   ├── registry.nomad.hcl
│   │   ├── dufs.nomad.hcl
│   │   ├── jaeger.nomad.hcl
│   │   └── deploy-infra.ps1         # 一键部署全部基础设施
│   └── traefik/                      # Traefik 反向代理
│       ├── traefik.nomad.hcl
│       └── deploy.ps1
│
├── scripts/                          # 运维脚本
├── justfile                          # Monorepo 命令编排
├── .env.ps1                          # 🔒 凭证（gitignored）
└── README.md
```

---

## 部署

### 前置条件

- Windows + 远程服务器（运行 Nomad / Consul / Docker）
- 远程服务器已安装：Nomad、Consul、Docker、Spin CLI
- Windows 已安装：Spin CLI、Rust（wasm32-wasip1 target）、Node.js、TinyGo、Go 1.23.6
- ghcr.io 账号 + Personal Access Token

### 凭证配置

根目录 `.env.ps1`（已 gitignore）：

```powershell
$GhcrUser = "your-github-username"
$GhcrToken = "ghp_your_personal_access_token"
$SpinExe = "C:\path\to\spin.exe"
$NomadAddr = "http://localhost:4646"
$Registry = "localhost:15000"
```

远程服务器 Spin 登录（raw_exec 拉取 OCI 镜像需要）：

```bash
/usr/local/bin/spin registry login ghcr.io -u <username> -p <token>
```

### 部署命令

```powershell
# 部署基础设施（Redis、Placement、Registry、dufs、Jaeger）
.\IaC\nomad\deploy-infra.ps1

# 部署 Traefik 反向代理
.\IaC\traefik\deploy.ps1

# 部署 Spin 应用（方案一）
.\spin-app\deploy.ps1 go          # Go 应用
.\spin-app\deploy.ps1 rust        # Rust 应用
.\spin-app\deploy.ps1 js          # JavaScript 应用
.\spin-app\deploy.ps1 ts          # TypeScript 应用
.\spin-app\deploy.ps1 python      # Python 应用

# 停止 Spin 应用
.\spin-app\deploy.ps1 go stop

# 部署 Binding 应用（方案二）
.\dapr-bindings\deploy.ps1 go
.\dapr-bindings\deploy.ps1 rust

# 停止 Binding 应用
.\dapr-bindings\deploy.ps1 go stop
```

或使用 `just` 命令编排：

```bash
just deploy-all          # 部署全部
just spin-deploy go      # 部署单个 Spin 应用
just binding-deploy      # 部署 Binding 应用
just health spin-go-app  # 健康检查
just health-binding      # Binding 健康检查
```

### deploy.ps1 执行流程

**Spin 应用**：本地编译 WASM → 推送 ghcr.io OCI → 读取 `spin-app.nomad.hcl` 模板替换占位符 → Nomad HTTP API 提交 Job → Force reschedule

**Binding 应用**：TinyGo 编译 WASM → `wsl curl -T` 上传到 dufs → 读取 `dapr-bindings.nomad.hcl` 模板替换占位符 → Nomad HTTP API 提交 Job

### 内存配置

deploy.ps1 根据语言自动设置 Nomad 内存限制：

| 语言 | spin-webhost memory | spin-webhost memory_max | dapr-sidecar memory |
|---|---|---|---|
| Rust | 256 MB | 512 MB | 256 MB |
| Go | 256 MB | 512 MB | 256 MB |
| JS | 1024 MB | 4096 MB | 512 MB |
| TS | 512 MB | 2048 MB | 256 MB |
| Python | 512 MB | 2048 MB | 256 MB |


---

## 架构全景

```
                        ┌─────────────────────────────────────────────────────────────┐
                        │                    远程服务器 (Nomad + Consul + Docker)       │
                        │                                                             │
  外部客户端 ──────────→ │  Traefik (:80)                                              │
                        │    │                                                        │
                        │    ├── /spin-go-app/*     → Dapr (:3500) → Spin Go (:80)    │
                        │    ├── /spin-rust-app/*   → Dapr (:3500) → Spin Rust (:80)  │
                        │    ├── /spin-js-app/*     → Dapr (:3500) → Spin JS (:80)    │
                        │    ├── /spin-ts-app/*     → Dapr (:3500) → Spin TS (:80)    │
                        │    ├── /spin-python-app/* → Dapr (:3500) → Spin Python (:80)│
                        │    └── /dapr-bindings/*   → Dapr (:3500) → WASM binding     │
                        │                                                             │
                        │  基础设施 Jobs:                                               │
                        │    Redis (:6379)  │  Dapr Placement (:50000)                │
                        │    Registry (:15000)  │  dufs (:5555)  │  Jaeger            │
                        │                                                             │
                        │  Consul (:8500) — 服务发现 + Traefik 路由源                   │
                        └─────────────────────────────────────────────────────────────┘
                                                      │
  Windows (开发机) ──── deploy.ps1 ──→ Nomad API (:4646)
                        build WASM → push ghcr.io / dufs
```

### 关键设计

- **bridge 网络模式**：每个 Nomad Job 的 Spin + Dapr 共享同一网络命名空间，内部通过 `127.0.0.1` 通信，外部只暴露 Dapr 端口
- **Consul 服务发现**：Placement、Redis、dufs 地址全部通过 Consul template 动态解析，不硬编码 IP
- **Traefik 自动路由**：基于 Consul Catalog provider，应用注册时带 `traefik.enable=true` tag 即自动生成路由规则
- **统一模板**：`spin-app.nomad.hcl` 和 `dapr-bindings.nomad.hcl` 是参数化模板，deploy.ps1 替换 `<<APP_NAME>>` 等占位符后提交

---

## 换基础设施？改 YAML，不改代码

业务代码永远只向 `http://127.0.0.1:3500` 发请求，后端是什么由 Nomad HCL 中的 Dapr component template 决定：

<details>
<summary>当前默认：Redis（state + pubsub）</summary>

```yaml
apiVersion: dapr.io/v1alpha1
kind: Component
metadata:
  name: statestore
spec:
  type: state.redis
  version: v1
  metadata:
    - name: redisHost
      value: "{{ range service "redis" }}{{ .Address }}:{{ .Port }}{{ end }}"
```
</details>

<details>
<summary>切换到 AWS DynamoDB</summary>

```yaml
spec:
  type: state.aws.dynamodb
  version: v1
  metadata:
    - name: region
      value: "ap-southeast-1"
    - name: table
      value: "my-state-table"
```
</details>

<details>
<summary>Pub/Sub 切换到 Kafka</summary>

```yaml
spec:
  type: pubsub.kafka
  version: v1
  metadata:
    - name: brokers
      value: "kafka-broker:9092"
```
</details>

**业务代码零修改。**

---

## AI Prompt 速查表

以下 Prompt 可以直接复制给任何 LLM，生成的代码无需修改即可在本架构中运行：

| 场景 | Prompt 关键句 |
|---|---|
| 保存状态 | "向 `http://127.0.0.1:3500/v1.0/state/statestore` POST 一个 KV JSON 数组" |
| 读取状态 | "从 `http://127.0.0.1:3500/v1.0/state/statestore/{key}` GET" |
| 发布消息 | "向 `http://127.0.0.1:3500/v1.0/publish/pubsub/{topic}` POST 消息体" |
| 服务调用 | "向 `http://127.0.0.1:3500/v1.0/invoke/{app-id}/method/{path}` 发请求" |
| HTTP 出站 | "向 `http://127.0.0.1:3500/v1.0/bindings/{binding-name}` POST binding 请求" |

核心思路：**所有基础设施操作 = 向 Dapr sidecar 发 HTTP 请求**。AI 不需要知道背后是 Redis 还是 DynamoDB。

---

## 🤝 贡献

欢迎 PR：更多语言模板、更多 Dapr 组件配置、文档改进、Bug 报告。

## 📜 License

[Apache-2.0](LICENSE)

---

<p align="center">
  <sub>AI 写逻辑 · WASM 跑沙箱 · Dapr 管基建 — Cloud Native 3.0</sub>
</p>
