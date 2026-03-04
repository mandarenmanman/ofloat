#!/bin/bash
echo "=== 直接测试 Dapr pubsub API ==="
resp=$(curl -s -w "\n%{http_code}" -X POST "http://localhost/spin-js-app/v1.0/publish/pubsub/test-topic" \
  -H "content-type: application/json" \
  -d '{"msg":"direct-test"}')
code=$(echo "$resp" | tail -1)
body=$(echo "$resp" | head -1)
echo "Direct Dapr API: code=$code body=$body"

echo ""
echo "=== 通过应用路由测试 pubsub ==="
resp=$(curl -s -w "\n%{http_code}" -X POST "http://localhost/spin-js-app/v1.0/invoke/spin-js-app/method/publish/test-topic" \
  -H "content-type: application/json" \
  -d '{"msg":"app-route-test"}')
code=$(echo "$resp" | tail -1)
body=$(echo "$resp" | head -1)
echo "App route: code=$code body=$body"
