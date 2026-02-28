---
inclusion: manual
---

# 创建新 Spin 应用脚手架指南

当用户要求创建一个新的 Spin WASM 应用时，按以下步骤完整执行。

## 1. 确认信息

向用户确认：
- 应用名称（例如 `order-service`，最终目录为 `spin-order-service/`）
- 语言选择：Rust 或 JavaScript
- Dapr 端口（当前已占用：3500, 3501, 3502，按顺序分配下一个）
- Dapr gRPC 端口（当前已占用：50001, 50002, 50003）
- Metrics 端口（当前已占用：9091, 9092, 9093）

## 2. 使用 Spin CLI 初始化项目

Spin CLI 路径：`E:\spin-v3.6.2-windows-amd64\spin.exe`

**Rust 应用：**
```powershell
E:\spin-v3.6.2-windows-amd64\spin.exe new -t http-rust spin-{name}
```

**JavaScript 应用：**
```powershell
E:\spin-v3.6.2-windows-amd64\spin.exe new -t http-js spin-{name}
```

初始化后 Spin 会自动生成基础项目结构（spin.toml、src 目录、构建配置等）。
然后在此基础上进行以下修改：

1. 修改 `spin.toml`：添加 `allowed_outbound_hosts` 包含 Dapr 地址
2. 创建 `deploy.ps1`：部署脚本
3. 创建 `spin-{name}.nomad.hcl`：Nomad Job 定义
4. 修改业务代码：按项目模板编写 HTTP handler

JS 应用初始化后还需要安装 itty-router：
```powershell
npm install itty-router
```

## 3. 目录结构

```
spin-{name}/
├── src/
│   ├── lib.rs          # Rust
│   └── index.js        # JavaScript
├── spin.toml
├── deploy.ps1
├── spin-{name}.nomad.hcl
├── Cargo.toml          # Rust only
├── package.json        # JS only
├── build.mjs           # JS only
└── .gitignore          # JS only
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

参考 #[[file:spin-js-app/deploy.ps1]] 的结构，替换以下变量：
- `$ImageTag` = `"spin-{name}:latest"`
- Job 名称 = `"spin-{name}"`
- HCL 文件名 = `"spin-{name}.nomad.hcl"`
- 构建命令：Rust 用 `& $SpinExe build`，JS 用 `npm run build`

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

## 5. 创建后检查清单

- [ ] `spin.toml` 的 `allowed_outbound_hosts` 包含正确的 Dapr 地址
- [ ] `.nomad.hcl` 中 docker config 有 `ports = ["dapr-http", "dapr-grpc"]`
- [ ] `.nomad.hcl` 中端口号不与现有应用冲突
- [ ] `deploy.ps1` 从根目录加载 `.env.ps1`
- [ ] `/health` 路由已实现
- [ ] 告知用户需要在 WSL 中 `spin registry login ghcr.io` 后才能部署

## 6. 构建并部署

创建完所有文件后，自动执行以下步骤：

1. 安装依赖（JS: `npm install`，Rust: 跳过）
2. 构建验证（`npm run build` 或 `spin build`）
3. 执行部署脚本：`.\spin-{name}\deploy.ps1`
4. 用 WSL curl 验证 health 接口：`wsl bash -c "curl -s http://localhost:{dapr_port}/v1.0/invoke/spin-{name}/method/health"`

## 7. 更新全局 steering

创建完成后，更新 `.kiro/steering/project-architecture.md` 中的端口占用列表，以及本文件中的端口占用列表。
