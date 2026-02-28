# 🧠 WasmDapr-AI-Stack: AI 写代码，从第一行到上线

![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)
![WASM](https://img.shields.io/badge/WebAssembly-Enabled-orange)
![Dapr](https://img.shields.io/badge/Dapr-v1.16.9-blue)
![Spin](https://img.shields.io/badge/Fermyon_Spin-v3.6.2-lightgrey)
![AI Native](https://img.shields.io/badge/AI_Code-100%25_Friendly-brightgreen)

> **一句话**：让 AI 只写业务逻辑，基础设施的事全部消失。从 Prompt 到生产部署，端到端零摩擦。

---

## 痛点：AI 生成代码为什么总是"差一点"？

你让 AI 帮你写一个微服务，它会给你一堆 Redis SDK 初始化、Kafka 连接池配置、云厂商鉴权代码……
这些"胶水代码"占了 80%，AI 在这些地方最容易出错，你也最不想 review 它们。

**根本原因**：传统架构把业务逻辑和基础设施耦合在一起，AI 需要处理的上下文太大了。

## 解法：关注点彻底分离

```
┌─────────────────────────────────────────────────────────┐
│                    你（或 AI）只需要写这一层              │
│                                                         │
│   fn handle_request(req) -> Response {                  │
│       // 纯粹的 HTTP 数据处理                            │
│       // 向 localhost:3500 发 HTTP 请求 = 操作任何基础设施 │
│   }                                                     │
│                                                         │
├─────────────────────────────────────────────────────────┤
│  Spin (WASM 沙箱)    │  Dapr (基础设施抽象)              │
│  微秒级冷启动          │  Redis/Kafka/DynamoDB 全透明     │
│  几百 KB 内存          │  换后端只改 YAML，代码零修改       │
└─────────────────────────────────────────────────────────┘
```

| 层 | 谁负责 | 关心什么 |
|---|---|---|
| 业务逻辑 | AI / 开发者 | 只写 HTTP handler，向 `localhost:3500` 发请求 |
| 运行时沙箱 | Spin (WASM) | 微秒启动、内存隔离、极简二进制 |
| 基础设施 | Dapr Sidecar | 状态存储、消息队列、分布式追踪，全部通过 HTTP API 暴露 |
| 编排部署 | Nomad + OCI Registry | PowerShell 脚本一键 build → push → deploy |

---

## 🚀 端到端体验：从 Prompt 到生产

### Step 1 — 让 AI 写业务代码

把这段 Prompt 丢给任何 LLM（ChatGPT / Copilot / Kiro）：

**Rust 版本：**

```text
我在用 Fermyon Spin SDK (spin-sdk 5.2.0) 写 Rust HTTP 组件。
帮我写一个 handler：
- GET /health 返回 {"status":"healthy"}
- POST /state 时，把请求体转发到 http://127.0.0.1:3500/v1.0/state/statestore
- POST /publish/:topic 时，把请求体转发到 http://127.0.0.1:3500/v1.0/publish/pubsub/:topic
只用标准 HTTP 调用，不引入任何第三方 SDK。
```

**JavaScript 版本：**

```text
我在用 Fermyon Spin JS SDK 写 JavaScript HTTP 组件，使用 itty-router。
帮我写一个 handler：
- GET /health 返回 {"status":"healthy"}
- POST /state 时，把请求体转发到 http://127.0.0.1:3501/v1.0/state/statestore
- GET /state/:key 时，从 http://127.0.0.1:3501/v1.0/state/statestore/:key 读取
- POST /publish/:topic 时，把请求体转发到 http://127.0.0.1:3501/v1.0/publish/pubsub/:topic
只用标准 fetch API，不引入任何第三方 SDK。
```

项目包含两个示例应用：

**Rust App** (`spin-rust-app/src/lib.rs`)：

```rust
use spin_sdk::http::{IntoResponse, Request, Response};
use spin_sdk::http_component;

#[http_component]
fn handle_request(req: Request) -> anyhow::Result<impl IntoResponse> {
    match req.path() {
        "/health" => Ok(Response::builder()
            .status(200)
            .header("content-type", "application/json")
            .body(r#"{"status":"healthy"}"#)
            .build()),
        _ => Ok(Response::builder()
            .status(200)
            .body("Hello from WASM + Dapr")
            .build()),
    }
}
```

**JS App** (`spin-js-app/src/index.js`)：

```javascript
import { AutoRouter } from 'itty-router';
const DAPR_URL = 'http://127.0.0.1:3501';
let router = AutoRouter();

router
    .get('/health', () => new Response(
        JSON.stringify({ status: 'healthy' }),
        { headers: { 'content-type': 'application/json' } }
    ))
    .post('/state', async (req) => {
        const body = await req.text();
        const resp = await fetch(`${DAPR_URL}/v1.0/state/statestore`, {
            method: 'POST',
            headers: { 'content-type': 'application/json' },
            body,
        });
        return new Response(resp.body, { status: resp.status });
    });
```

注意看：**没有 Redis SDK，没有 Kafka client，没有任何云厂商依赖**。所有基础设施操作 = 向 Dapr sidecar 发 HTTP 请求。

### Step 2 — 一键部署

开发环境在 Windows + WSL 上运行，部署脚本为 PowerShell。

```powershell
# 1. WSL 中启动 Nomad dev 模式（另开一个终端）
nomad agent -dev

# 2. 部署基础设施（在 WSL 中执行）
nomad job run nomad/redis.nomad.hcl
nomad job run nomad/dapr-placement.nomad.hcl
nomad job run nomad/registry.nomad.hcl

# 3. WSL 中登录 ghcr.io（raw_exec 拉取镜像需要）
/usr/local/bin/spin registry login ghcr.io -u <username> -p <token>

# 4. Windows PowerShell 中部署应用（build → push ghcr.io → nomad submit）
.\spin-js-app\deploy.ps1
.\spin-rust-app\deploy.ps1
```

脚本自动完成：编译 WASM → 推送到 ghcr.io → 通过 Nomad HTTP API 提交 Job → Nomad 的 raw_exec 从 OCI registry 拉取并启动。

### Step 3 — 验证

```bash
# Rust App（通过 Dapr Sidecar）
curl http://localhost:3500/v1.0/invoke/spin-app/method/health
# → {"status":"healthy"}

# JS App（通过 Dapr Sidecar）
curl http://localhost:3501/v1.0/invoke/spin-js-app/method/health
# → {"status":"healthy"}

# Nomad UI（浏览器打开）
# → http://localhost:4646
```

**整个过程：写一个函数 → 跑一个脚本 → curl 验证。没了。**

---

## 💡 AI Prompt 速查表

以下 Prompt 可以直接复制给任何 LLM，生成的代码无需修改即可在本架构中运行：

| 场景 | Prompt 关键句 |
|---|---|
| 保存状态 | "向 `http://127.0.0.1:3500/v1.0/state/statestore` POST 一个 KV JSON 数组" |
| 读取状态 | "从 `http://127.0.0.1:3500/v1.0/state/statestore/{key}` GET" |
| 发布消息 | "向 `http://127.0.0.1:3500/v1.0/publish/pubsub/{topic}` POST 消息体" |
| 服务调用 | "向 `http://127.0.0.1:3500/v1.0/invoke/{app-id}/method/{path}` 发请求" |

核心思路：**所有基础设施操作 = 向 Dapr sidecar 发 HTTP 请求**。AI 不需要知道背后是 Redis 还是 DynamoDB。

---

## 📐 架构全景

```text
[User / AI Agent]
       │  只写 HTTP handler
       ▼
┌──────────── Nomad (dev mode) ──────────────────┐
│                                                 │
│  Job: spin-app (Rust)                          │
│  ┌──────────────────────────────────┐          │
│  │ Spin WASM :80  │  Dapr :3500    │          │
│  │ (raw_exec)     │  (docker)      │          │
│  │ --from-registry ghcr.io/...     │          │
│  └──────────────────────────────────┘          │
│                                                 │
│  Job: spin-js-app (JavaScript)                 │
│  ┌──────────────────────────────────┐          │
│  │ Spin WASM :80  │  Dapr :3501    │          │
│  │ (raw_exec)     │  (docker)      │          │
│  │ --from-registry ghcr.io/...     │          │
│  └──────────────────────────────────┘          │
│                                                 │
│  Job: redis          (:6379)                   │
│  Job: registry       (:15000)                  │
│  Job: dapr-placement (:50000)                  │
│                                                 │
│  Nomad UI: http://localhost:4646               │
└─────────────────────────────────────────────────┘
                      │
                      ▼
        [Redis / Kafka / DynamoDB / ...]
```

| 服务 | 端口 | 作用 |
|---|---|---|
| `spin-app` (Rust WASM) | 80 (内部) | Rust 业务代码，raw_exec driver |
| `spin-js-app` (JS WASM) | 80 (内部) | JavaScript 业务代码，raw_exec driver |
| `dapr-sidecar` (Rust) | 3500 | Rust App 的 Dapr API 网关 |
| `dapr-sidecar` (JS) | 3501 | JS App 的 Dapr API 网关 |
| `redis` | 6379 | 默认状态存储 & 消息队列后端 |
| `dapr-placement` | 50000 | Actor 放置服务 |
| `registry` | 15000 | 本地 OCI 镜像仓库（备用） |

---

## ⚙️ 换基础设施？改 YAML，不改代码

你的业务代码永远只向 Dapr sidecar 发请求，后端是什么由 Nomad HCL 中的 Dapr component template 决定：

<details>
<summary>当前默认：Redis</summary>

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
      value: "172.26.64.1:6379"
```
</details>

<details>
<summary>切换到 AWS DynamoDB</summary>

```yaml
apiVersion: dapr.io/v1alpha1
kind: Component
metadata:
  name: statestore
spec:
  type: state.aws.dynamodb
  version: v1
  metadata:
    - name: region
      value: "ap-southeast-1"
    - name: table
      value: "my-state-table"
    - name: accessKey
      value: "<YOUR_ACCESS_KEY>"
    - name: secretKey
      value: "<YOUR_SECRET_KEY>"
```
</details>

<details>
<summary>切换到阿里云 TableStore</summary>

```yaml
apiVersion: dapr.io/v1alpha1
kind: Component
metadata:
  name: statestore
spec:
  type: state.alicloud.tablestore
  version: v1
  metadata:
    - name: endpoint
      value: "https://your-instance.cn-hangzhou.ots.aliyuncs.com"
    - name: accessKeyID
      value: "<YOUR_ACCESS_KEY_ID>"
    - name: accessKeySecret
      value: "<YOUR_ACCESS_KEY_SECRET>"
    - name: instanceName
      value: "your-instance"
    - name: tableName
      value: "my-state-table"
```
</details>

<details>
<summary>Pub/Sub 切换到 Kafka</summary>

```yaml
apiVersion: dapr.io/v1alpha1
kind: Component
metadata:
  name: pubsub
spec:
  type: pubsub.kafka
  version: v1
  metadata:
    - name: brokers
      value: "kafka-broker:9092"
    - name: authType
      value: "none"
```
</details>

**业务代码零修改。** 这就是 Dapr 的价值。

---

## 📂 项目结构

```text
.
├── spin-rust-app/                    # Rust WASM 应用
│   ├── src/lib.rs                    # 🧠 业务逻辑
│   ├── Cargo.toml                    # 依赖：spin-sdk + anyhow
│   ├── spin.toml                     # Spin 路由配置
│   ├── spin-rust-app.nomad.hcl       # Nomad Job 定义（Spin + Dapr sidecar）
│   └── deploy.ps1                    # 一键部署脚本（PowerShell）
│
├── spin-js-app/                      # JavaScript WASM 应用
│   ├── src/index.js                  # 🧠 业务逻辑
│   ├── package.json                  # 依赖：itty-router + spin SDK
│   ├── build.mjs                     # esbuild 构建脚本
│   ├── spin.toml                     # Spin 路由配置
│   ├── spin-js-app.nomad.hcl         # Nomad Job 定义（Spin + Dapr sidecar）
│   └── deploy.ps1                    # 一键部署脚本（PowerShell）
│
├── nomad/                            # 基础设施 Nomad Jobs
│   ├── redis.nomad.hcl               # Redis 服务
│   ├── dapr-placement.nomad.hcl      # Dapr Placement 服务
│   └── registry.nomad.hcl            # 本地 OCI 镜像仓库
│
├── .env.ps1                          # 🔒 ghcr.io 凭证（gitignored）
├── .gitignore
└── README.md
```

---

## 🚢 部署详解

### 前置条件

- Windows + WSL2
- WSL 中安装：[Docker](https://docs.docker.com/get-docker/)、[Nomad](https://developer.hashicorp.com/nomad/install)、[Fermyon Spin v3.6.2](https://developer.fermyon.com/spin/v2/install)
- Windows 中安装：[Fermyon Spin v3.6.2](https://developer.fermyon.com/spin/v2/install)（用于构建和推送）
- Rust App 额外需要：[Rust](https://rustup.rs/) + `rustup target add wasm32-wasip1`
- JS App 额外需要：[Node.js](https://nodejs.org/)
- [GitHub Container Registry](https://ghcr.io) 账号 + Personal Access Token

### 凭证配置

在项目根目录创建 `.env.ps1`（已 gitignore）：

```powershell
$GhcrUser = "your-github-username"
$GhcrToken = "ghp_your_personal_access_token"
```

WSL 中也需要登录一次（Nomad raw_exec 拉取时需要）：

```bash
/usr/local/bin/spin registry login ghcr.io -u <username> -p <token>
```

### 部署流程

```powershell
# 部署 JS App
.\spin-js-app\deploy.ps1

# 部署 Rust App
.\spin-rust-app\deploy.ps1

# 停止某个 App
.\spin-js-app\deploy.ps1 -Action stop
.\spin-rust-app\deploy.ps1 -Action stop
```

deploy.ps1 执行流程：
1. 本地编译 WASM（`npm run build` 或 `spin build`）
2. 登录 ghcr.io 并推送 OCI 镜像
3. 通过 Nomad HTTP API（localhost:4646）提交 Job
4. Force reschedule 确保更新生效

### Nomad 架构说明

每个应用是一个 Nomad Job，包含两个 Task 共享 bridge 网络 namespace：

- `spin-webhost`（raw_exec）：从 ghcr.io 拉取 WASM 镜像，监听 namespace 内部 `:80`
- `dapr-sidecar`（docker）：Dapr 进程，连接 Spin 的 `:80`，对外暴露 Dapr HTTP 端口

bridge 模式确保 Spin 和 Dapr 在同一网络空间，外部只能通过 Dapr 端口访问。

### 常用命令（WSL）

```bash
# 查看所有 job 状态
nomad job status

# 查看某个 app 详情
nomad job status spin-js-app
nomad job status spin-app

# 查看 alloc 日志
nomad alloc logs <alloc-id> spin-webhost
nomad alloc logs <alloc-id> dapr-sidecar
```

---

## 🤝 贡献

欢迎 PR：更多语言模板 (Go/TinyGo, Python)、更多 Dapr 组件配置、文档改进、Bug 报告。

## 📜 License

[Apache-2.0](LICENSE)

---

<p align="center">
  <sub>AI 写逻辑 · WASM 跑沙箱 · Dapr 管基建 — Cloud Native 3.0</sub>
</p>
