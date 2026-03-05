#!/bin/bash
# dapr-bindings 接口测试脚本
# 用法: wsl bash dapr-bindings/go/test-api.sh
# 通过 Traefik 路由 → Dapr Bindings API 测试 WASM binding

BINDINGS="http://localhost/dapr-bindings/v1.0/bindings/wasm"

PASS=0
FAIL=0

green() { echo -e "\e[32m[PASS]\e[0m $1"; PASS=$((PASS+1)); }
red()   { echo -e "\e[31m[FAIL]\e[0m $1 — $2"; FAIL=$((FAIL+1)); }

# 调用 binding：$1=stdin json string（会被放进 data 字段，需要转义为 JSON string）
invoke() {
  local inner="$1"
  local escaped
  escaped=$(printf '%s' "$inner" | sed 's/\\/\\\\/g; s/"/\\"/g')
  local payload="{\"operation\":\"execute\",\"data\":\"${escaped}\"}"
  resp=$(curl -s -w "\n%{http_code}" -X POST "$BINDINGS" \
    -H "Content-Type: application/json" \
    -d "$payload")
  echo "$resp"
}

parse() {
  code=$(echo "$1" | tail -1)
  body=$(echo "$1" | sed '$d')
}

echo "=== dapr-bindings 接口测试 ==="
echo ""

# 1. health（空输入）
echo "--- 1. health (empty input) ---"
resp=$(curl -s -w "\n%{http_code}" -X POST "$BINDINGS" \
  -H "Content-Type: application/json" \
  -d '{"operation":"execute","data":""}')
parse "$resp"
if [ "$code" = "200" ] && echo "$body" | grep -q '"healthy"'; then
  green "健康检查-空输入 (200, status=healthy)"
else
  red "健康检查-空输入" "code=$code body=$body"
fi

# 2. health（action）
echo "--- 2. health (action) ---"
parse "$(invoke '{"action":"health"}')"
if [ "$code" = "200" ] && echo "$body" | grep -q '"healthy"'; then
  green "健康检查-action (200, status=healthy)"
else
  red "健康检查-action" "code=$code body=$body"
fi

# 3. echo
echo "--- 3. echo ---"
parse "$(invoke '{"action":"echo","data":"hello wasm"}')"
if [ "$code" = "200" ] && echo "$body" | grep -q 'hello wasm'; then
  green "echo (200, 包含 hello wasm)"
else
  red "echo" "code=$code body=$body"
fi

# 4. http-test
echo "--- 4. http-test ---"
parse "$(invoke '{"action":"http-test"}')"
if [ "$code" = "200" ] && echo "$body" | grep -q '"http-test"'; then
  if echo "$body" | grep -q '"get_status"'; then
    green "http-test (200, 包含 get_status)"
  else
    red "http-test" "响应缺少 get_status: body=$body"
  fi
else
  red "http-test" "code=$code body=$body"
fi

# 5. unknown action
echo "--- 5. unknown action ---"
parse "$(invoke '{"action":"foobar"}')"
if [ "$code" = "200" ] && echo "$body" | grep -q '"error"'; then
  green "unknown action (200, 返回 error)"
else
  red "unknown action" "code=$code body=$body"
fi

# 6. invalid json（echo 兜底）
echo "--- 6. invalid json ---"
resp=$(curl -s -w "\n%{http_code}" -X POST "$BINDINGS" \
  -H "Content-Type: application/json" \
  -d '{"operation":"execute","data":"not-json-at-all"}')
parse "$resp"
if [ "$code" = "200" ] && echo "$body" | grep -q '"echo"'; then
  green "invalid json (200, 回退到 echo)"
else
  red "invalid json" "code=$code body=$body"
fi

# 汇总
echo ""
echo "=== 结果: $PASS 通过, $FAIL 失败 ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
