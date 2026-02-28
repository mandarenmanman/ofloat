# 🧠 WasmDapr-AI-Stack: AI 写代码，从第一行到上线

![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)
![WASM](https://img.shields.io/badge/WebAssembly-Enabled-orange)
![Dapr](https://img.shields.io/badge/Dapr-v1.16.9-blue)
![Spin](https://img.shields.io/badge/Fermyon_Spin-v2.0-lightgrey)
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
| 编排部署 | Nomad | `bash deploy-nomad.sh` 一键搞定 |

---

## 🚀 端到端体验：从 Prompt 到生产

### Step 1 — 让 AI 写业务代码

把这段 Prompt 丢给任何 LLM（ChatGPT / Copilot / Kiro）：

```text
我在用 Fermyon Spin SDK (spin-sdk 5.2.0) 写 Rust HTTP 组件。
帮我写一个 handler：
- GET /health 返回 {"status":"healthy"}
- POST /orders 时，把请求体转发到 http://127.0.0.1:3500/v1.0/publish/pubsub/orders
- POST /state 时，把请求体转发到 http://127.0.0.1:3500/v1.0/state/statestore
只用标准 HTTP 调用，不引入任何第三方 SDK。
```

AI 生成的代码大概长这样（这也是项目里 `spin-app/src/lib.rs` 的真实结构）：

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
        // ... 你的业务逻辑
        _ => Ok(Response::builder()
            .status(200)
            .body("Hello from WASM + Dapr")
            .build()),
    }
}
```

注意看：**没有 Redis SDK，没有 Kafka client，没有任何云厂商依赖**。`Cargo.toml` 里只有两个依赖：

```toml
[dependencies]
anyhow = "1"
spin-sdk = "5.2.0"
```

这就是 AI 需要理解的全部上下文。

### Step 2 — 一键部署（Nomad）

```bash
# 1. 启动 Nomad dev 模式（另开一个终端）
nomad agent -dev

# 2. 先部署基础设施（redis、placement、registry）
nomad job run nomad/redis.nomad.hcl
nomad job run nomad/dapr-placement.nomad.hcl
nomad job run nomad/registry.nomad.hcl

# 3. 构建并部署应用
bash deploy-nomad.sh
```

脚本自动完成：编译 WASM → 部署文件到 `/opt/spin-app` → 启动 Spin + Dapr Sidecar + Dashboard。

### Step 3 — 验证

```bash
# 通过 Dapr Sidecar 调用你的 WASM 应用
curl http://localhost:3500/v1.0/invoke/spin-app/method/health
# → {"status":"healthy"}

# Dapr Dashboard（浏览器打开）
# → http://localhost:8080

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

核心思路：**所有基础设施操作 = 向 `localhost:3500` 发 HTTP 请求**。AI 不需要知道背后是 Redis 还是 DynamoDB。

---

## 📐 架构全景

```text
[User / AI Agent]
       │  只写 HTTP handler
       ▼
┌──────────── Nomad (dev mode) ──────────┐
│                                        │
│  Spin Engine          Dapr Sidecar     │
│  ┌──────────┐   HTTP  ┌──────────┐    │
│  │WASM Core │ ──────▶ │State/MQ  │    │
│  │(AI Code) │         │Components│    │
│  │  :80     │         │  :3500   │    │
│  └──────────┘         └──────────┘    │
│  (raw_exec)           (docker)        │
│                             │          │
└─────────────────────────────┼──────────┘
                              ▼
            [Redis / Kafka / DynamoDB / ...]
```

| 服务 | 端口 | 作用 |
|---|---|---|
| `spin-webhost` (WASM) | 80 (内部) | 运行你的业务代码（raw_exec driver） |
| `dapr-sidecar` | 3500 | Dapr API 网关，所有基础设施操作的统一入口 |
| `redis` | 6379 | 默认状态存储 & 消息队列后端 |
| `dapr-dashboard` | 8080 | 可视化管理面板 |
| `dapr-placement` | 50000 | Actor 放置服务 |
| `registry` | 15000 | 本地 OCI 镜像仓库 |

---

## ⚙️ 换基础设施？改 YAML，不改代码

这是"零厂商锁定"的实际含义。你的 `lib.rs` 永远只向 `localhost:3500` 发请求，后端是什么由 `dapr/components/*.yaml` 决定：

<details>
<summary>当前默认：Redis</summary>

```yaml
# dapr/components/statestore.yaml
apiVersion: dapr.io/v1alpha1
kind: Component
metadata:
  name: statestore
spec:
  type: state.redis
  version: v1
  metadata:
    - name: redisHost
      value: "redis:6379"
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
├── spin-app/
│   ├── src/lib.rs              # 🧠 唯一需要 AI 写的文件
│   ├── Cargo.toml              # 依赖：spin-sdk + anyhow，仅此而已
│   ├── spin.toml               # 路由 & 网络权限配置
│   └── run.sh                  # Spin 启动脚本
├── dapr/
│   ├── components/
│   │   ├── statestore.yaml     # 状态存储后端配置
│   │   └── pubsub.yaml         # 消息队列后端配置
│   └── config/config.yaml      # 追踪、指标、日志
├── nomad/
│   ├── spin-app.nomad.hcl      # Spin WASM (raw_exec) + Dapr Sidecar (docker)
│   ├── redis.nomad.hcl         # Redis 服务
│   ├── dapr-placement.nomad.hcl # Dapr Placement 服务
│   ├── dapr-dashboard.nomad.hcl # Dapr Dashboard
│   └── registry.nomad.hcl      # 本地 OCI 镜像仓库
├── deploy-nomad.sh             # Nomad 一键部署脚本
└── README.md
```

---

## 🚢 Nomad 部署

比 K8s 轻量得多，单二进制文件，dev 模式秒启动。

### 前置条件

- [Docker](https://docs.docker.com/get-docker/)
- [Nomad](https://developer.hashicorp.com/nomad/install)
- [Rust](https://rustup.rs/) + `rustup target add wasm32-wasip1`
- [Fermyon Spin CLI](https://developer.fermyon.com/spin/v2/install)

### 快速部署

```bash
# 1. 启动 Nomad dev 模式（另开一个终端）
nomad agent -dev

# 2. 部署基础设施
nomad job run nomad/redis.nomad.hcl
nomad job run nomad/dapr-placement.nomad.hcl
nomad job run nomad/registry.nomad.hcl

# 3. 构建并部署应用
bash deploy-nomad.sh

# 4. 验证
curl http://localhost:3500/v1.0/invoke/spin-app/method/health

# 5. 停止全部服务
bash deploy-nomad.sh stop
```

### deploy-nomad.sh 用法

```bash
bash deploy-nomad.sh            # 构建 WASM 并部署应用 + Dashboard
bash deploy-nomad.sh app-only   # 只重新部署 spin-app（跳过构建）
bash deploy-nomad.sh stop       # 停止并清除全部 Nomad jobs
```

### Nomad 架构

```text
┌──────────────── Nomad (dev mode) ────────────────┐
│                                                   │
│  Job: spin-app (group: spin-dapr)                │
│  ┌─────────────────────────────────────┐          │
│  │  Task: spin-webhost  │ Task: daprd  │          │
│  │  (raw_exec :80)      │ (docker:3500)│          │
│  │  共享网络 namespace                   │          │
│  └─────────────────────────────────────┘          │
│                                                   │
│  Job: redis          (:6379)                      │
│  Job: registry       (:15000)                     │
│  Job: dapr-placement (:50000)                     │
│  Job: dapr-dashboard (:8080)                      │
│                                                   │
│  Nomad UI: http://localhost:4646                  │
└───────────────────────────────────────────────────┘
```

### 常用命令

```bash
# 查看所有 job 状态
nomad job status

# 查看 spin-app 详情
nomad job status spin-app

# 查看日志
nomad alloc logs <alloc-id> spin-webhost
nomad alloc logs <alloc-id> dapr-sidecar

# 扩缩容（修改 count 后）
nomad job run nomad/spin-app.nomad.hcl
```

---

## 🤝 贡献

欢迎 PR：更多语言模板 (Go/TinyGo, JS/QuickJS)、更多 Dapr 组件配置、文档改进、Bug 报告。

## 📜 License

[Apache-2.0](LICENSE)

---

<p align="center">
  <sub>AI 写逻辑 · WASM 跑沙箱 · Dapr 管基建 — Cloud Native 3.0</sub>
</p>
