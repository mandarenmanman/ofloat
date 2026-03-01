---
inclusion: manual
---

# 创建新 Spin 应用脚手架指南

当用户要求创建一个新的 Spin WASM 应用时，按以下步骤完整执行。

## 1. 确认信息

向用户确认：
- 应用名称（例如 `order-service`，最终目录为 `spin-order-service/`）
- 语言选择：Rust / JavaScript / TypeScript / Go / Python
- Dapr 端口（当前已占用：3500, 3501, 3502, 3504, 3505, 3506，按顺序分配下一个）
- Dapr gRPC 端口（当前已占用：50001-50008）
- Metrics 端口（当前已占用：9091-9098）

## 1.1 语言编码规范

根据用户选择的语言，参考对应的编码规范 steering 文件：

- Go: #[[file:.kiro/steering/spin-go.md]]
- Rust: #[[file:.kiro/steering/spin-rust.md]]
- JavaScript: #[[file:.kiro/steering/spin-js.md]]
- TypeScript: #[[file:.kiro/steering/spin-ts.md]]
- Python: #[[file:.kiro/steering/spin-python.md]]

这些文件包含各语言的依赖版本、代码模板、Dapr 调用方式和注意事项，创建新应用时必须严格遵循。

## 2. 初始化项目

Spin CLI 路径：`E:\spin-v3.6.2-windows-amd64\spin.exe`

### 方式 A：使用 Spin CLI 模板（Rust / JS / TS / Go / Python）

```powershell
# Rust
E:\spin-v3.6.2-windows-amd64\spin.exe new -t http-rust spin-{name}

# JavaScript
E:\spin-v3.6.2-windows-amd64\spin.exe new -t http-js spin-{name}

# TypeScript
E:\spin-v3.6.2-windows-amd64\spin.exe new -t http-ts spin-{name}

# Go
E:\spin-v3.6.2-windows-amd64\spin.exe new -t http-go spin-{name}

# Python
E:\spin-v3.6.2-windows-amd64\spin.exe new -t http-py spin-{name}
```

初始化后 Spin 会自动生成基础项目结构（spin.toml、src 目录、构建配置等）。
然后在此基础上进行以下修改：

1. 修改 `spin.toml`：添加 `allowed_outbound_hosts` 包含 Dapr 地址
2. 创建 `spin-{name}.nomad.hcl`：Nomad Job 定义
3. 创建 `deploy.ps1`：部署脚本（最后创建，触发自动部署 hook）
4. 修改业务代码：按对应语言的 steering 编码规范编写 HTTP handler

JS/TS 应用初始化后还需要安装 itty-router：
```powershell
npm install itty-router
```

## 3. 目录结构

```
spin-{name}/
├── src/
│   ├── lib.rs          # Rust
│   ├── index.js        # JavaScript
│   └── index.ts        # TypeScript
├── main.go             # Go（不在 src 下）
├── app.py              # Python（不在 src 下）
├── spin.toml
├── deploy.ps1
├── spin-{name}.nomad.hcl
├── Cargo.toml          # Rust only
├── go.mod / go.sum     # Go only
├── package.json        # JS/TS only
├── build.mjs           # JS/TS only
├── tsconfig.json       # TS only
├── requirements.txt    # Python only
└── .gitignore
```

## 4. 文件模板

### spin.toml（通用）

```toml
spin_manifest_version = 2

[application]
name = "spin-{name}"
version = "0.1.0"
description = "{description}"

[[trigger.http]]
route = "/..."
component = "spin-{name}"

[component.spin-{name}]
source = "{wasm_path}"                    # Rust: target/wasm32-wasip1/release/spin_{name_underscore}.wasm
                                          # JS: dist/spin-{name}.wasm
allowed_outbound_hosts = [
    "http://127.0.0.1:{dapr_port}",
]
[component.spin-{name}.build]
command = "{build_command}"               # Rust: "cargo build --target wasm32-wasip1 --release"
                                          # JS: ["npm install", "npm run build"]
```

### deploy.ps1（通用模板）

根据语言参考对应的 deploy.ps1：
- Rust: 参考 #[[file:spin-rust-app/deploy.ps1]]
- JavaScript: 参考 #[[file:spin-js-app/deploy.ps1]]
- TypeScript: 参考 #[[file:spin-ts-app/deploy.ps1]]
- Go: 参考 #[[file:spin-go-app/deploy.ps1]]（含 Go 1.25 GOROOT 切换逻辑）
- Python: 参考 #[[file:spin-python-app/deploy.ps1]]（含 venv 创建逻辑）

替换以下变量：
- `$ImageTag` = `"spin-{name}:latest"`
- Job 名称 = `"spin-{name}"`
- HCL 文件名 = `"spin-{name}.nomad.hcl"`

### spin-{name}.nomad.hcl

参考 #[[file:spin-js-app/spin-js-app.nomad.hcl]] 的结构，替换：
- job 名称 = `"spin-{name}"`
- `--from-registry` = `"ghcr.io/mandarenmanman/spin-{name}:latest"`
- `-app-id` = `"spin-{name}"`
- `-dapr-http-port` = `"{dapr_port}"`（新分配的端口）
- `-dapr-grpc-port` = `"{grpc_port}"`（新分配的端口）
- `-metrics-port` = `"{metrics_port}"`（新分配的端口）
- `static` 端口映射与上面一致
- docker config 中必须有 `ports = ["dapr-http", "dapr-grpc"]`

### Rust 专用文件

**Cargo.toml：**
```toml
[package]
name = "spin-{name_underscore}"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["cdylib"]

[dependencies]
anyhow = "1"
spin-sdk = "5.2.0"

[workspace]
```

**src/lib.rs：**
参考 #[[file:spin-rust-app/src/lib.rs]] 的结构，替换 app-id 和 Dapr 端口。

### JavaScript 专用文件

**package.json：**
参考 #[[file:spin-js-app/package.json]]，替换 name 和 wasm 输出文件名。

**build.mjs：**
直接复制 #[[file:spin-js-app/build.mjs]]。

**src/index.js：**
参考 #[[file:spin-js-app/src/index.js]] 的结构，替换 DAPR_URL 端口。

**.gitignore：**
```
node_modules/
dist/
build/
```

### TypeScript 专用文件

**package.json：**
参考 #[[file:spin-ts-app/package.json]]，替换 name 和 wasm 输出文件名。

**build.mjs：**
直接复制 #[[file:spin-ts-app/build.mjs]]。

**tsconfig.json：**
直接复制 #[[file:spin-ts-app/tsconfig.json]]。

**src/index.ts：**
参考 #[[file:spin-ts-app/src/index.ts]] 的结构，替换 DAPR_URL 端口。

**.gitignore：**
```
node_modules/
dist/
build/
```

### Go 专用文件

**go.mod：**
参考 #[[file:spin-go-app/go.mod]]，替换 module 名称。

**go.sum：**
直接复制 #[[file:spin-go-app/go.sum]]（依赖相同）。

**main.go：**
参考 #[[file:spin-go-app/main.go]] 的结构，替换 daprURL 端口和 app-id。

**.gitignore：**
```
main.wasm
```

### Python 专用文件

**requirements.txt：**
参考 #[[file:spin-python-app/requirements.txt]]。

**app.py：**
参考 #[[file:spin-python-app/app.py]] 的结构，替换 Dapr 端口。

**.gitignore：**
```
__pycache__/
venv/
app.wasm
```

## 5. 文件创建顺序

**`deploy.ps1` 必须是最后一个创建的文件。** 因为有 hook 监听 `spin-*/deploy.ps1` 的 fileCreated 事件，会自动触发部署流程。如果其他文件（业务代码、spin.toml、.nomad.hcl、go.mod/package.json 等）还没写完就创建了 deploy.ps1，部署必然失败。

严格按以下顺序创建文件：
1. `.gitignore`
2. 依赖文件（`go.mod`/`go.sum`、`Cargo.toml`、`package.json`/`build.mjs`、`requirements.txt`）
3. 业务代码（`main.go`、`src/lib.rs`、`src/index.js`、`app.py`）
4. `spin.toml`
5. `spin-{name}.nomad.hcl`
6. **`deploy.ps1`（最后）**

## 6. 创建后检查清单

- [ ] `spin.toml` 的 `allowed_outbound_hosts` 包含正确的 Dapr 地址
- [ ] `.nomad.hcl` 中 docker config 有 `ports = ["dapr-http", "dapr-grpc"]`
- [ ] `.nomad.hcl` 中端口号不与现有应用冲突
- [ ] `deploy.ps1` 从根目录加载 `.env.ps1`
- [ ] `/health` 路由已实现
- [ ] 告知用户需要在 WSL 中 `spin registry login ghcr.io` 后才能部署

## 7. 自动部署

`deploy.ps1` 创建后会被 hook（`auto-deploy-spin`）自动捕获并触发部署流程，无需手动执行。hook 会提示 agent 执行部署脚本并验证 health 接口。

## 8. 更新全局 steering

创建完成后，更新 `.kiro/steering/project-architecture.md` 中的端口占用列表，以及本文件中的端口占用列表。
