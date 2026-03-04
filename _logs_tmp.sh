#!/bin/bash
NOMAD_ADDR="http://localhost:4646"
ALLOC_ID=$(curl -s "$NOMAD_ADDR/v1/job/dapr-bindings/allocations" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[0]['ID'])")
echo "=== stdout ==="
curl -s "$NOMAD_ADDR/v1/client/fs/logs/$ALLOC_ID?task=dapr-sidecar&type=stdout&plain=true" | tail -20
echo ""
echo "=== stderr ==="
curl -s "$NOMAD_ADDR/v1/client/fs/logs/$ALLOC_ID?task=dapr-sidecar&type=stderr&plain=true" | tail -20
