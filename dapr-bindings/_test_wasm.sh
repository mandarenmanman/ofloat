#!/bin/bash
# Test dapr wasm binding via Traefik
URL="http://localhost/dapr-bindings/v1.0/bindings/wasm"

echo "=== health ==="
curl -s -X POST "$URL" \
  -H "Content-Type: application/json" \
  -d '{"operation":"execute","data":{"action":"health"}}'
echo ""

echo "=== echo ==="
curl -s -X POST "$URL" \
  -H "Content-Type: application/json" \
  -d '{"operation":"execute","data":{"action":"echo","data":"hello wasm"}}'
echo ""

echo "=== upper ==="
curl -s -X POST "$URL" \
  -H "Content-Type: application/json" \
  -d '{"operation":"execute","data":{"action":"upper","data":"hello wasm"}}'
echo ""
