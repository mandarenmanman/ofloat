#!/bin/bash
# 测试 spin-js-app POST /state

# 从 Consul 获取服务地址
SVC=$(curl -s http://127.0.0.1:8500/v1/catalog/service/spin-js-app)
ADDR=$(echo "$SVC" | python3 -c "import sys,json; s=json.load(sys.stdin)[0]; print(f\"{s['ServiceAddress']}:{s['ServicePort']}\")")

echo "spin-js-app 地址: $ADDR"

# POST 保存状态
echo "--- POST /state ---"
resp=$(curl -s -w "\n%{http_code}" -X POST "http://${ADDR}/v1.0/invoke/spin-js-app/method/state" \
  -H "Content-Type: application/json" \
  -d '[{"key":"test","value":"hello world123"}]')
code=$(echo "$resp" | tail -1)
body=$(echo "$resp" | sed '$d')
echo "Status: $code"
echo "Body: $body"

# GET 读取状态验证
echo "--- GET /state/test ---"
resp=$(curl -s -w "\n%{http_code}" "http://${ADDR}/v1.0/invoke/spin-js-app/method/state/test")
code=$(echo "$resp" | tail -1)
body=$(echo "$resp" | sed '$d')
echo "Status: $code"
echo "Body: $body"
