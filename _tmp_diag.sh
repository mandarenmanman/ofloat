#!/bin/bash
# Find latest alloc for spin-js-app and get dapr-sidecar logs
ALLOC_ID=$(curl -s http://localhost:4646/v1/job/spin-js-app/allocations | python3 -c "
import sys, json
allocs = json.load(sys.stdin)
allocs.sort(key=lambda a: a['CreateTime'], reverse=True)
if allocs: print(allocs[0]['ID'])
")

echo "=== Alloc: $ALLOC_ID ==="

echo ""
echo "=== dapr-sidecar stderr ==="
curl -s "http://localhost:4646/v1/client/fs/logs/$ALLOC_ID?task=dapr-sidecar&type=stderr&plain=true" 2>/dev/null | tail -50

echo ""
echo "=== dapr-sidecar stdout ==="
curl -s "http://localhost:4646/v1/client/fs/logs/$ALLOC_ID?task=dapr-sidecar&type=stdout&plain=true" 2>/dev/null | tail -50

echo ""
echo "=== spin-webhost stderr ==="
curl -s "http://localhost:4646/v1/client/fs/logs/$ALLOC_ID?task=spin-webhost&type=stderr&plain=true" 2>/dev/null | tail -30

echo ""
echo "=== Rendered env.txt ==="
curl -s "http://localhost:4646/v1/client/fs/cat/$ALLOC_ID?path=dapr-sidecar/local/env.txt" 2>/dev/null
