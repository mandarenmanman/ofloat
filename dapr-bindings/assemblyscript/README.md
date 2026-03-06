# Dapr WASM Binding — AssemblyScript

与 Go 版一致：通过 wasi-http（types / streams / default-outgoing-HTTP）发 HTTP，供 Dapr wazero host 调用。

## 编译

```bash
npm install
npm run build
```

构建产物：`build/bindings.wasm`。

查看该 wasm 的 imports（排查 `module[env] not instantiated`）：

```bash
npm run check-imports
```

## 在 Dapr 中运行

当前 AssemblyScript 构建会导入 **`env.abort`**，而 Dapr 的 wazero 运行时**不提供** `env` 模块，因此会报错：

```text
error invoking output binding wasm: module[env] not instantiated
```

**解决办法：在 Dapr 中不要使用本目录的 wasm，改用 Go 或 TS 构建的 wasm。**

- **Go**：`.\deploy.ps1 go`，使用 `dapr-bindings/go` 下 TinyGo 编译的 wasm（与 Dapr wasi-http 兼容）。
- **TS**：`.\deploy.ps1 ts`，使用 `dapr-bindings/ts` 下 Javy 编译的 wasm（内嵌 JS 引擎，无需 env）。

本目录的 wasm 适用于提供 `env` 的 wasi 运行时（如 wasmtime 等），或后续 Dapr 支持注入 `env` 时再使用。
