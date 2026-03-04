#!/bin/bash
# spin-js-app 接口测试脚本
# 用法: wsl bash spin-js-app/test-api.sh
# 通过 Traefik 路由 + Dapr Service Invocation API 测试所有端点

# Traefik 入口 + Dapr invoke 前缀
INVOKE="http://localhost/spin-js-app/v1.0/invoke/spin-js-app/method"
# 状态管理直接走 Dapr state API
STATE="http://localhost/spin-js-app/v1.0/state/statestore"
# 发布消息走 Dapr pubsub API
PUBSUB="http://localhost/spin-js-app/v1.0/publish/pubsub"

PASS=0
FAIL=0

green() { echo -e "\e[32m[PASS]\e[0m $1"; PASS=$((PASS+1)); }
red()   { echo -e "\e[31m[FAIL]\e[0m $1 — $2"; FAIL=$((FAIL+1)); }

echo "=== spin-js-app 接口测试 ==="
echo "Invoke URL: $INVOKE"
echo ""

# 1. 健康检查
echo "--- 1. GET /health ---"
resp=$(curl -s -w "\n%{http_code}" "$INVOKE/health")
code=$(echo "$resp" | tail -1)
body=$(echo "$resp" | head -1)
if [ "$code" = "200" ] && echo "$body" | grep -q '"healthy"'; then
  green "健康检查 (200, status=healthy)"
else
  red "健康检查" "code=$code body=$body"
fi

# 2. 首页
echo "--- 2. GET / ---"
resp=$(curl -s -w "\n%{http_code}" "$INVOKE/")
code=$(echo "$resp" | tail -1)
body=$(echo "$resp" | sed '$d')
if [ "$code" = "200" ] && echo "$body" | grep -q 'Spin JS'; then
  green "首页 (200, 包含 Spin JS)"
else
  red "首页" "code=$code"
fi

# 3. 保存状态
echo "--- 3. POST /state (via Dapr State API) ---"
code=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$STATE" \
  -H "content-type: application/json" \
  -d '[{"key":"test-key","value":"hello-wasm"}]')
if [ "$code" = "204" ] || [ "$code" = "200" ]; then
  green "保存状态 ($code)"
else
  red "保存状态" "code=$code"
fi

# 4. 读取状态
echo "--- 4. GET /state/test-key (via Dapr State API) ---"
resp=$(curl -s -w "\n%{http_code}" "$STATE/test-key")
code=$(echo "$resp" | tail -1)
body=$(echo "$resp" | head -1)
if [ "$code" = "200" ] && echo "$body" | grep -q 'hello-wasm'; then
  green "读取状态 (200, value=hello-wasm)"
else
  red "读取状态" "code=$code body=$body"
fi

# 5. 发布消息
echo "--- 5. POST /publish/test-topic (via Dapr PubSub API) ---"
code=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$PUBSUB/test-topic" \
  -H "content-type: application/json" \
  -d '{"msg":"test from spin-js-app"}')
if [ "$code" = "204" ] || [ "$code" = "200" ]; then
  green "发布消息 ($code)"
else
  red "发布消息" "code=$code"
fi

# 6. 读取不存在的 key
echo "--- 6. GET /state/nonexistent (via Dapr State API) ---"
resp=$(curl -s -w "\n%{http_code}" "$STATE/nonexistent")
code=$(echo "$resp" | tail -1)
if [ "$code" = "204" ] || [ "$code" = "200" ]; then
  green "读取不存在的 key ($code, 空响应)"
else
  red "读取不存在的 key" "code=$code"
fi

# 汇总
echo ""
echo "=== 结果: $PASS 通过, $FAIL 失败 ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
