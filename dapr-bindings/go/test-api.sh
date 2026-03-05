#!/bin/bash
# dapr-bindings 接口测试脚本
# 用法: wsl bash dapr-bindings/test-api.sh
# 通过 Traefik 路由 → Dapr Bindings API 测试 WASM binding

BINDINGS="http://localhost/dapr-bindings/v1.0/bindings/wasm"

PASS=0
FAIL=0

green() { echo -e "\e[32m[PASS]\e[0m $1"; PASS=$((PASS+1)); }
red()   { echo -e "\e[31m[FAIL]\e[0m $1 — $2"; FAIL=$((FAIL+1)); }

# 调用 binding：$1=stdin json string（会被放进 data 字段，需要转义为 JSON string）
invoke() {
  local inner="$1"
  # 把内层 JSON 转义成合法的 JSON string value：转义 \ 和 "
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

# 1. health
echo "--- 1. health ---"
parse "$(invoke '{"action":"health"}')"
if [ "$code" = "200" ] && echo "$body" | grep -q '"healthy"'; then
  green "健康检查 (200, status=healthy)"
else
  red "健康检查" "code=$code body=$body"
fi

# 2. echo
echo "--- 2. echo ---"
parse "$(invoke '{"action":"echo","data":"hello wasm"}')"
if [ "$code" = "200" ] && echo "$body" | grep -q 'hello wasm'; then
  green "echo (200, 包含 hello wasm)"
else
  red "echo" "code=$code body=$body"
fi

# 3. upper
echo "--- 3. upper ---"
parse "$(invoke '{"action":"upper","data":"hello world"}')"
if [ "$code" = "200" ] && echo "$body" | grep -q 'HELLO WORLD'; then
  green "upper (200, HELLO WORLD)"
else
  red "upper" "code=$code body=$body"
fi

# 4. save-state
echo "--- 4. save-state ---"
parse "$(invoke '{"action":"save-state","data":{"key":"test-key","value":"hello-wasm"}}')"
if [ "$code" = "200" ] && echo "$body" | grep -q '"ok"'; then
  green "save-state (200, status=ok)"
else
  red "save-state" "code=$code body=$body"
fi

# 5. get-state
echo "--- 5. get-state ---"
parse "$(invoke '{"action":"get-state","data":"test-key"}')"
if [ "$code" = "200" ] && echo "$body" | grep -q 'hello-wasm'; then
  green "get-state (200, value=hello-wasm)"
else
  red "get-state" "code=$code body=$body"
fi

# 6. publish
echo "--- 6. publish ---"
parse "$(invoke '{"action":"publish","data":{"topic":"test-topic","data":{"msg":"test from binding"}}}')"
if [ "$code" = "200" ] && echo "$body" | grep -q '"ok"'; then
  green "publish (200, status=ok)"
else
  red "publish" "code=$code body=$body"
fi

# 7. delete-state
echo "--- 7. delete-state ---"
parse "$(invoke '{"action":"delete-state","data":"test-key"}')"
if [ "$code" = "200" ] && echo "$body" | grep -q '"ok"'; then
  green "delete-state (200, status=ok)"
else
  red "delete-state" "code=$code body=$body"
fi

# 8. get-state 确认已删除
echo "--- 8. get-state (deleted) ---"
parse "$(invoke '{"action":"get-state","data":"test-key"}')"
if [ "$code" = "200" ] && echo "$body" | grep -q '"value":null'; then
  green "get-state deleted (200, value=null)"
else
  red "get-state deleted" "code=$code body=$body"
fi

# 9. unknown action
echo "--- 9. unknown action ---"
parse "$(invoke '{"action":"foobar"}')"
if [ "$code" = "200" ] && echo "$body" | grep -q '"error"'; then
  green "unknown action (200, 返回 error)"
else
  red "unknown action" "code=$code body=$body"
fi

# 汇总
echo ""
echo "=== 结果: $PASS 通过, $FAIL 失败 ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
