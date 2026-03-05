#!/bin/bash
# 编译为 WASI wasm，供 Dapr WASM binding (wazero + stealthrocket/wasi-go wasi-http) 使用
# 必须用 TinyGo，且 dev-wasm-go 版本与 Dapr 官方 testdata 一致，才能匹配 host ABI
# 用法: bash build.sh 或 wsl bash dapr-bindings/go/build.sh
set -e
cd "$(dirname "$0")"
if ! command -v tinygo &>/dev/null; then
  echo "需要安装 TinyGo: https://tinygo.org/getting-started/install/"
  exit 1
fi
tinygo build -o app.wasm --no-debug -target=wasi .
echo "Built app.wasm (TinyGo wasi)"
