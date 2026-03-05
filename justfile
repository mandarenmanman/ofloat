# WasmDapr-AI-Stack Monorepo Justfile
# 用法: just <recipe> [args]
# 列出所有命令: just --list

# 默认列出可用命令
default:
    @just --list

# ===== Spin 应用 (方案一) =====

# 部署 spin 应用: just spin-deploy rust|go|js|ts|python
spin-deploy lang:
    powershell -ExecutionPolicy Bypass -File spin-app/{{lang}}/deploy.ps1

# 停止 spin 应用: just spin-stop rust|go|js|ts|python
spin-stop lang:
    powershell -ExecutionPolicy Bypass -File spin-app/{{lang}}/deploy.ps1 -Action stop

# 部署所有 spin 应用
spin-deploy-all:
    just spin-deploy rust
    just spin-deploy go
    just spin-deploy js
    just spin-deploy ts
    just spin-deploy python

# 停止所有 spin 应用
spin-stop-all:
    just spin-stop rust
    just spin-stop go
    just spin-stop js
    just spin-stop ts
    just spin-stop python

# ===== Dapr Binding 应用 (方案二) =====

# 部署 dapr-bindings: just binding-deploy
binding-deploy:
    powershell -ExecutionPolicy Bypass -File dapr-bindings/go/deploy.ps1

# 停止 dapr-bindings: just binding-stop
binding-stop:
    powershell -ExecutionPolicy Bypass -File dapr-bindings/go/deploy.ps1 -Action stop

# ===== 基础设施 =====

# 部署基础设施 (redis, dapr-placement, registry, dufs)
infra-deploy:
    powershell -ExecutionPolicy Bypass -File nomad/deploy-infra.ps1

# 停止基础设施
infra-stop:
    powershell -ExecutionPolicy Bypass -File nomad/deploy-infra.ps1 -Action stop

# 查看基础设施状态
infra-status:
    powershell -ExecutionPolicy Bypass -File nomad/deploy-infra.ps1 -Action status

# 部署 Traefik
traefik-deploy:
    powershell -ExecutionPolicy Bypass -File traefik/deploy.ps1

# ===== 全量操作 =====

# 部署全部: 基础设施 + Traefik + 所有应用
deploy-all:
    just infra-deploy
    just traefik-deploy
    just spin-deploy-all
    just binding-deploy

# 停止全部
stop-all:
    just spin-stop-all
    just binding-stop
    just infra-stop

# ===== 验证 =====

# 检查服务健康状态 (通过 WSL curl)
[no-exit-message]
health app-id:
    wsl curl -s http://localhost/{{app-id}}/health

# 检查 binding 健康状态
[no-exit-message]
health-binding:
    wsl curl -s -X POST http://localhost/dapr-bindings/v1.0/bindings/wasm -H "Content-Type: application/json" -d '{"operation":"execute","data":"{\"action\":\"health\"}"}'
