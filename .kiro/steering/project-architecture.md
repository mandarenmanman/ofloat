---
inclusion: always
---

# WasmDapr-AI-Stack 项目架构规则

## 工具链版本

| 工具 | 版本 | 备注 |
|---|---|---|
| Spin CLI | v3.6.2 | Windows amd64 |
| Dapr (daprd) | 1.16.9 | Docker 镜像 `daprio/daprd:1.16.9` |
| Nomad | v1.11.2 | 运行在 WSL 中 |
| Rust spin-sdk | 5.2.0 | Cargo.toml |
| Go spin-go-sdk | v2.2.1 | go.mod |
| TinyGo | 0.40.x | 要求 Go 1.25.x |
| JS/TS @spinframework/build-tools | 1.0.4 | package.json |
| JS/TS @spinframework/wasi-http-proxy | 1.0.0 | package.json |
| Python spin-sdk | 3.1.0 | requirements.txt |
| Python componentize-py | 0.13.3 | requirements.txt |
| itty-router (JS/TS) | 5.0.18 | package.json |
| Node.js | v22.17.0 | 构建 JS/TS 用 |

## 核心原则

本项目采用 Spin WASM + Dapr Sidecar 架构，业务代码与基础设施完全解耦。

- 业务代码只写 HTTP handler，所有基础设施操作通过向 Dapr sidecar 发 HTTP 请求完成
- 绝对不要在业务代码中引入 Redis、Kafka、数据库等基础设施 SDK
- 绝对不要在业务代码中硬编码云厂商依赖

## Dapr API 约定

业务代码通过以下 HTTP API 与 Dapr sidecar 交互（全部是 localhost）：

| 操作 | 方法 | URL |
|---|---|---|
| 保存状态 | POST | `http://127.0.0.1:{dapr-port}/v1.0/state/statestore` |
| 读取状态 | GET | `http://127.0.0.1:{dapr-port}/v1.0/state/statestore/{key}` |
| 删除状态 | DELETE | `http://127.0.0.1:{dapr-port}/v1.0/state/statestore/{key}` |
| 发布消息 | POST | `http://127.0.0.1:{dapr-port}/v1.0/publish/pubsub/{topic}` |
| 服务调用 | ANY | `http://127.0.0.1:{dapr-port}/v1.0/invoke/{app-id}/method/{path}` |

当前应用的 Dapr 端口：
- spin-app (Rust): 3500
- spin-js-app (JS): 3501
- spin-order-service (JS): 3502
- spin-go-app (Go): 3504
- spin-ts-app (TS): 3505
- spin-python-app (Python): 3506

## 项目结构

```
spin-rust-app/          # Rust WASM 应用
  src/lib.rs            # 业务逻辑入口
  Cargo.toml            # 依赖只有 spin-sdk + anyhow
  spin.toml             # Spin 路由配置
  spin-rust-app.nomad.hcl  # Nomad Job 定义
  deploy.ps1            # 部署脚本

spin-js-app/            # JavaScript WASM 应用
  src/index.js          # 业务逻辑入口
  package.json          # 依赖只有 itty-router + spin SDK
  spin.toml             # Spin 路由配置
  spin-js-app.nomad.hcl # Nomad Job 定义
  deploy.ps1            # 部署脚本

spin-go-app/            # Go WASM 应用
  main.go               # 业务逻辑入口
  go.mod                # 依赖只有 spin-go-sdk
  spin.toml             # Spin 路由配置
  spin-go-app.nomad.hcl # Nomad Job 定义
  deploy.ps1            # 部署脚本（含 Go 1.25 切换逻辑）

spin-ts-app/            # TypeScript WASM 应用
  src/index.ts          # 业务逻辑入口
  package.json          # 依赖同 JS 应用 + typescript
  tsconfig.json         # TypeScript 配置
  spin.toml             # Spin 路由配置
  spin-ts-app.nomad.hcl # Nomad Job 定义
  deploy.ps1            # 部署脚本

spin-python-app/        # Python WASM 应用
  app.py                # 业务逻辑入口
  requirements.txt      # 依赖只有 spin-sdk + componentize-py
  spin.toml             # Spin 路由配置
  spin-python-app.nomad.hcl # Nomad Job 定义
  deploy.ps1            # 部署脚本（含 venv 创建逻辑）

nomad/                  # 基础设施
  redis.nomad.hcl
  dapr-placement.nomad.hcl
  registry.nomad.hcl
```

## 新增应用的模式

如果用户要创建新的 Spin 应用，按以下模式：
1. 在项目根目录创建 `spin-{name}/` 目录
2. 复制对应语言模板的结构（Rust 或 JS）
3. 分配新的 Dapr 端口（当前已用：3500, 3501, 3502）
4. 创建对应的 `.nomad.hcl` 和 `deploy.ps1`
5. `spin.toml` 中 `allowed_outbound_hosts` 必须包含 Dapr sidecar 地址
6. 当前已用 Dapr 端口：3500, 3501, 3502, 3504, 3505, 3506；gRPC 端口：50001-50007；metrics 端口：9091-9097

## 部署相关

- 部署脚本是 PowerShell (.ps1)，在 Windows 上执行
- WASM 制品推送到 ghcr.io OCI registry
- Nomad Job 通过 HTTP API (localhost:4646) 提交，不用 nomad CLI
- 凭证在根目录 `.env.ps1` 中，已 gitignore
- Nomad 运行在 WSL 中，Spin 用 raw_exec driver 从 ghcr.io 拉取 WASM

## Nomad Job 注意事项

### 内存配置
- Spin WASM 进程在启动阶段（"Preparing Wasm modules"）内存消耗较高，如果 Nomad 分配的内存不足，进程会被 OOM Kill（Exit Code 137）
- JS WASM 应用启动内存开销比 Rust 大，`spin-webhost` task 建议：
  - Rust 应用：`memory = 256`，`memory_max = 512`
  - Go 应用：`memory = 256`，`memory_max = 512`（产物小，接近 Rust）
  - Python 应用：`memory = 512`，`memory_max = 2048`（内嵌 CPython 解释器，接近 JS）
  - JS/TS 应用：`memory = 512`，`memory_max = 2048`
- Dapr sidecar task 建议 `memory = 256`，最低不低于 128

### Dapr Sidecar 配置要点
- Docker 镜像必须用 `daprio/daprd`（运行时），不要用 `daprio/dapr`（基础镜像）
- command 必须是 `./daprd`，不要用 `./placement`（那是放置服务）
- daprd 参数用单横线 `-app-id`，不要用双横线 `--app-id`
- 必须通过 template 挂载 component 文件（statestore.yaml、pubsub.yaml）和 config.yaml，否则 Dapr 无法连接 Redis
- `-placement-host-address` 使用 `172.26.64.1:50000`
- 每个服务的 `-metrics-port` 必须不同，避免冲突
