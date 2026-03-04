#!/bin/bash
set -e
NOMAD_ADDR="http://localhost:4646"
JOB_FILE="/mnt/d/github/ofloat/dapr-bindings/dapr-bindings.nomad.hcl"

# Purge old failed job
curl -s -X DELETE "$NOMAD_ADDR/v1/job/dapr-bindings?purge=true" > /dev/null
echo "[INFO] Purged old job"
sleep 2

JOB_HCL=$(cat "$JOB_FILE")
PARSED=$(curl -s "$NOMAD_ADDR/v1/jobs/parse" -X POST \
  -d "{\"JobHCL\":$(python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" <<< "$JOB_HCL")}" \
  -H "Content-Type: application/json")
if echo "$PARSED" | grep -q '"ID"'; then
  curl -s "$NOMAD_ADDR/v1/jobs" -X POST \
    -d "{\"Job\":$PARSED}" \
    -H "Content-Type: application/json" > /dev/null
  echo "[OK] dapr-bindings deployed (bridge mode)"
else
  echo "[ERROR] $PARSED"
  exit 1
fi

echo "[INFO] Waiting for daprd to start..."
sleep 25

# Check alloc
ALLOC_ID=$(curl -s "$NOMAD_ADDR/v1/job/dapr-bindings/allocations" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[0]['ID'] if d else 'none')")
STATUS=$(curl -s "$NOMAD_ADDR/v1/allocation/$ALLOC_ID" | python3 -c "import sys,json; print(json.load(sys.stdin)['ClientStatus'])")
echo "[INFO] Alloc status: $STATUS"

if [ "$STATUS" != "running" ]; then
  curl -s "$NOMAD_ADDR/v1/allocation/$ALLOC_ID" | python3 -c "
import sys,json
d=json.load(sys.stdin)
for name, state in d.get('TaskStates',{}).items():
    print('Task:', name, 'State:', state['State'])
    for e in state.get('Events',[])[-3:]:
        msg = e.get('DisplayMessage','') or e.get('Message','')
        print('  ', e['Type'], msg)
"
  exit 1
fi

# Test via Traefik
echo "[INFO] Testing via Traefik (port 80)..."
HTTP=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/dapr-bindings/v1.0/healthz)
echo "[INFO] healthz: $HTTP"

# Statestore
curl -s -X POST http://localhost/dapr-bindings/v1.0/state/statestore \
  -H "Content-Type: application/json" \
  -d '[{"key":"bridge-test","value":"hello-bridge"}]'
VAL=$(curl -s http://localhost/dapr-bindings/v1.0/state/statestore/bridge-test)
echo "[INFO] statestore: $VAL"

# Pubsub
PUB=$(curl -s -o /dev/null -w "%{http_code}" -X POST http://localhost/dapr-bindings/v1.0/publish/pubsub/test-topic \
  -H "Content-Type: application/json" \
  -d '{"msg":"hello-bridge"}')
echo "[INFO] pubsub: $PUB"
