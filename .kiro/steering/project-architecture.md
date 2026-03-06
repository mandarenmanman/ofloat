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
| TinyGo | 0.35.0 | 要求 Go 1.19~1.23（使用 go1.23.6） |
| JS/TS @spinframework/build-tools | 1.0.4 | package.json |
| JS/TS @spinframework/wasi-http-proxy | 1.0.0 | package.json |
| Python spin-sdk | 3.1.0 | requirements.txt |
| Python componentize-py | 0.13.3 | requirements.txt |
| itty-router (JS/TS) | 5.0.18 | package.json |
| Node.js | v22.17.0 | 构建 JS/TS 用 |
| Consul | 1.22.0 | 远程服务器运行，服务发现（注意：1.22.4+ UI 有已知 bug） |
| Traefik | v3.4 | Docker 镜像 `localhost:15000/traefik:v3.4` |
| dufs | v0.45.0 | 文件服务器，方案二 WASM 产物分发 |
| Just | latest | Monorepo 命令编排，根目录 justfile |

## 核心原则

本项目有两种 WASM + Dapr 架构模式，业务代码与基础设施完全解耦。

### 方案一：Spin WASM HTTP 应用（主流模式）
- 业务代码是 HTTP server，由 Spin 托管为长驻进程
- Dapr sidecar 通过 `-app-port` 与业务应用双向通信
- 支持 service invocation（可被其他服务调用）
- Nomad Job 包含两个 task：`spin-webhost` + `dapr-sidecar`
- 适用于：需要 HTTP API、路由、被其他服务调用的场景

### 方案二：Dapr WASM Binding（无 HTTP server）
- 业务代码是 stdin/stdout CLI 程序，编译成 `wasip1` WASM
- 没有 Spin 参与，WASM 产物上传到 dufs，Dapr 通过 `bindings.wasm` component 加载执行
- sidecar 无 `-app-port`，是唯一进程，按需启动 WASM
- 不支持 service invocation，只能通过 `/v1.0/bindings/wasm` API 调用
- Nomad Job 只有一个 task：`dapr-sidecar`
- 适用于：事件驱动、定时任务、轻量函数计算场景

### 通用原则
- 绝对不要在业务代码中引入 Redis、Kafka、数据库等基础设施 SDK
- 绝对不要在业务代码中硬编码云厂商依赖
- 两种方案的 WASM 代码内部都可以通过 Dapr HTTP API 操作状态和 pubsub

## Dapr API 约定

业务代码通过以下 HTTP API 与 Dapr sidecar 交互（全部是 localhost）：

| 操作 | 方法 | URL |
|---|---|---|
| 保存状态 | POST | `http://127.0.0.1:{dapr-port}/v1.0/state/statestore` |
| 读取状态 | GET | `http://127.0.0.1:{dapr-port}/v1.0/state/statestore/{key}` |
| 删除状态 | DELETE | `http://127.0.0.1:{dapr-port}/v1.0/state/statestore/{key}` |
| 发布消息 | POST | `http://127.0.0.1:{dapr-port}/v1.0/publish/pubsub/{topic}` |
| 服务调用 | ANY | `http://127.0.0.1:{dapr-port}/v1.0/invoke/{app-id}/method/{path}` |

各应用在 bridge 网络模式下使用默认 Dapr 端口（HTTP 3500、gRPC 50001），容器间互不冲突。

## 项目结构

```
spin-app/                       # 方案一：Spin WASM HTTP 应用
  spin-app.nomad.hcl            # 统一 Nomad Job 定义（所有语言共用）
  deploy.ps1                    # 统一部署脚本
  rust/                         # Rust WASM 应用
    src/lib.rs
    Cargo.toml
    spin.toml
  js/                           # JavaScript WASM 应用
    src/index.js
    package.json
    spin.toml
  go/                           # Go WASM 应用
    main.go
    go.mod
    spin.toml
  ts/                           # TypeScript WASM 应用
    src/index.ts
    package.json
    tsconfig.json
    spin.toml
  python/                       # Python WASM 应用
    app.py
    requirements.txt
    spin.toml

dapr-bindings/                  # 方案二：Dapr WASM Binding 应用
  dapr-bindings.nomad.hcl       # 统一 Nomad Job 定义
  deploy.ps1                    # 统一部署脚本
  go/                           # Go 实现
    main.go
    go.mod
    build.sh
    test-api.sh
    test-local.ps1
  rust/                         # Rust 实现
    src/main.rs
    Cargo.toml
    .devcontainer/

IaC/                            # 基础设施即代码
  consul/                       # Consul 配置与安装脚本
    consul.hcl
    install.sh
    start.sh
  dapr/                         # 自定义 daprd 镜像
    Dockerfile
    build-and-push.ps1
  nomad/                        # Nomad 配置与基础设施 Job
    server.hcl
    client.hcl
    redis.nomad.hcl
    dapr-placement.nomad.hcl
    registry.nomad.hcl
    dufs.nomad.hcl
    jaeger.nomad.hcl
    deploy-infra.ps1
    deploy-infra.sh
  traefik/                      # Traefik 反向代理
    traefik.nomad.hcl
    deploy.ps1

scripts/                        # 运维脚本
  check-consul-services.ps1
  check-dapr-bindings.ps1
```

## 新增应用的模式

### 新增 Spin 应用（方案一）
1. 在 `spin-app/` 下创建以语言命名的子目录（如 `spin-app/csharp/`）
2. 复制对应语言模板的结构（业务入口 + 依赖文件 + spin.toml）
3. 在 `spin-app/spin-app.nomad.hcl` 中添加对应的 task group
4. `spin.toml` 中 `allowed_outbound_hosts` 必须包含 Dapr sidecar 地址

### 新增 Binding 应用（方案二）
1. 在 `dapr-bindings/` 下创建以语言命名的子目录
2. 创建业务入口文件（stdin/stdout CLI 模式）和依赖文件
3. 在 `dapr-bindings/dapr-bindings.nomad.hcl` 中添加对应配置
4. 编译产物上传到 dufs

## 部署相关

- 部署脚本是 PowerShell (.ps1)，在 Windows 上执行
- WASM 制品推送到 ghcr.io OCI registry
- Nomad Job 通过 HTTP API (localhost:4646) 提交，不用 nomad CLI
- 凭证在根目录 `.env.ps1` 中，已 gitignore
- Nomad 运行在远程服务器（WSL 环境），Spin 用 raw_exec driver 从 ghcr.io 拉取 WASM
- 基础设施 Job（Redis、Placement、Registry 等）通过 `IaC/nomad/deploy-infra.ps1` 统一部署

## 测试与验证

- Nomad、Spin、Dapr sidecar 全部运行在远程服务器上，服务端口绑定在服务器网络命名空间内
- 部署后验证服务健康状态，必须通过 WSL 执行请求：`wsl curl -s http://localhost:{dapr-port}/v1.0/invoke/{app-id}/method/health`
- 绝对不要用 Windows 原生的 `curl.exe` 或 `Invoke-WebRequest` 去测试部署在远程服务器/Nomad 中的服务
- Consul UI 通过公网 IP 访问：`http://{server-ip}:8500/ui/`

## Nomad Job 注意事项

### 内存配置
- Spin WASM 进程在启动阶段（"Preparing Wasm modules"）内存消耗较高，如果 Nomad 分配的内存不足，进程会被 OOM Kill（Exit Code 137）
- `spin-webhost` task 建议：
  - Rust/Go 应用：`memory = 256`，`memory_max = 512`
  - Python/JS/TS 应用：`memory = 512`，`memory_max = 2048`
- Dapr sidecar task 建议 `memory = 256`，最低不低于 128

### Dapr Sidecar 配置要点
- Docker 镜像使用自定义 `localhost:15000/daprd:latest`（基于 `daprio/daprd`），daprd 二进制路径为 `/usr/local/bin/daprd`
- 使用 `entrypoint = ["/bin/sh", "-c"]` + shell 模式启动，以支持 `${ENV_VAR}` 环境变量展开
- daprd 参数用单横线 `-app-id`，不要用双横线 `--app-id`
- 必须通过 template 挂载 component 文件（statestore.yaml、pubsub.yaml）和 config.yaml，否则 Dapr 无法连接 Redis
- `-placement-host-address` 和 Redis 地址通过 Consul 服务发现动态解析，不要硬编码 IP
- 每个服务的 `-metrics-port` 在 bridge 网络模式下可使用默认端口，容器间互不冲突

### Consul 服务发现
- placement 地址通过 `{{ range service "dapr-placement" }}{{ .Address }}:{{ .Port }}{{ end }}` 解析，注入为 `PLACEMENT_ADDR` 环境变量
- Redis 地址通过 `{{ range service "redis" }}{{ .Address }}:{{ .Port }}{{ end }}` 解析，直接用在 statestore.yaml 和 pubsub.yaml 模板中
- 不要在 nomad job 中硬编码 IP 地址
