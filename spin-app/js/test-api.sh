#!/bin/bash
# spin-js-app 接口测试脚本
# 用法: wsl bash spin-js-app/test-api.sh
# 全部通过 Traefik 路由 + Dapr Service Invocation API 走应用路由

INVOKE="http://localhost/spin-js-app/v1.0/invoke/spin-js-app/method"

PASS=0
FAIL=0

green() { echo -e "\e[32m[PASS]\e[0m $1"; PASS=$((PASS+1)); }
red()   { echo -e "\e[31m[FAIL]\e[0m $1 — $2"; FAIL=$((FAIL+1)); }

echo "=== spin-js-app 接口测试 ==="
echo ""

# 1. 健康检查
URL="$INVOKE/health"
echo "--- 1. GET $URL ---"
resp=$(curl -s -w "\n%{http_code}" "$URL")
code=$(echo "$resp" | tail -1)
body=$(echo "$resp" | head -1)
if [ "$code" = "200" ] && echo "$body" | grep -q '"healthy"'; then
  green "健康检查 (200, status=healthy)"
else
  red "健康检查" "code=$code body=$body"
fi

# 2. 首页
URL="$INVOKE/"
echo "--- 2. GET $URL ---"
resp=$(curl -s -w "\n%{http_code}" "$URL")
code=$(echo "$resp" | tail -1)
body=$(echo "$resp" | sed '$d')
if [ "$code" = "200" ] && echo "$body" | grep -q 'Spin JS'; then
  green "首页 (200, 包含 Spin JS)"
else
  red "首页" "code=$code"
fi

# 3. 保存状态（走应用 /state 路由）
URL="$INVOKE/state"
echo "--- 3. POST $URL ---"
code=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$URL" \
  -H "content-type: application/json" \
  -d '[{"key":"test-key","value":"hello-wasm"}]')
if [ "$code" = "204" ] || [ "$code" = "200" ]; then
  green "保存状态 ($code)"
else
  red "保存状态" "code=$code"
fi

# 4. 读取状态（走应用 /state/:key 路由）
URL="$INVOKE/state/test-key"
echo "--- 4. GET $URL ---"
resp=$(curl -s -w "\n%{http_code}" "$URL")
code=$(echo "$resp" | tail -1)
body=$(echo "$resp" | head -1)
if [ "$code" = "200" ] && echo "$body" | grep -q 'hello-wasm'; then
  green "读取状态 (200, value=hello-wasm)"
else
  red "读取状态" "code=$code body=$body"
fi

# 5. 发布消息（走应用 /publish/:topic 路由）
URL="$INVOKE/publish/test-topic"
echo "--- 5. POST $URL ---"
code=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$URL" \
  -H "content-type: application/json" \
  -d '{"msg":"test from spin-js-app"}')
if [ "$code" = "204" ] || [ "$code" = "200" ]; then
  green "发布消息 ($code)"
else
  red "发布消息" "code=$code"
fi

# 6. 读取不存在的 key
URL="$INVOKE/state/nonexistent"
echo "--- 6. GET $URL ---"
resp=$(curl -s -w "\n%{http_code}" "$URL")
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
