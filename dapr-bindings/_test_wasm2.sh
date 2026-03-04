#!/bin/bash
URL="http://localhost/dapr-bindings/v1.0/bindings/wasm"

echo "=== raw string data ==="
curl -s -X POST "$URL" \
  -H "Content-Type: application/json" \
  -d '{"operation":"execute","data":"hello world"}'
echo ""

echo "=== json object as data ==="
curl -s -X POST "$URL" \
  -H "Content-Type: application/json" \
  -d '{"operation":"execute","data":{"action":"health"}}'
echo ""

echo "=== empty data ==="
curl -s -X POST "$URL" \
  -H "Content-Type: application/json" \
  -d '{"operation":"execute"}'
echo ""
