#!/bin/bash
# 测试 dapr-bindings WASM 的网络能力

echo "=== 1. save-state (测试 WASM 能否访问 sidecar) ==="
curl -s -X POST http://localhost/dapr-bindings/v1.0/bindings/wasm \
  -H "Content-Type: application/json" \
  -H "dapr-app-id: dapr-bindings" \
  -d '{"operation":"execute","data":"{\"action\":\"save-state\",\"data\":[{\"key\":\"test1\",\"value\":\"hello\"}]}"}'
echo

echo "=== 2. get-state (验证状态已保存) ==="
curl -s -X POST http://localhost/dapr-bindings/v1.0/bindings/wasm \
  -H "Content-Type: application/json" \
  -H "dapr-app-id: dapr-bindings" \
  -d '{"operation":"execute","data":"{\"action\":\"get-state\",\"data\":{\"key\":\"test1\"}}"}'
echo

echo "=== 3. check-js-app (测试 service invocation) ==="
curl -s -X POST http://localhost/dapr-bindings/v1.0/bindings/wasm \
  -H "Content-Type: application/json" \
  -H "dapr-app-id: dapr-bindings" \
  -d '{"operation":"execute","data":"{\"action\":\"check-js-app\",\"data\":{\"url\":\"http://127.0.0.1:3500/v1.0/invoke/spin-js-app/method/health\"}}"}'
echo
