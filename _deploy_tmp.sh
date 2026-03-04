#!/bin/bash
set -e
NOMAD_ADDR="http://localhost:4646"
JOB_FILE="$1"
JOB_HCL=$(cat "$JOB_FILE")
PARSED=$(curl -s "$NOMAD_ADDR/v1/jobs/parse" -X POST \
  -d "{\"JobHCL\":$(python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" <<< "$JOB_HCL")}" \
  -H "Content-Type: application/json")
if echo "$PARSED" | grep -q '"ID"'; then
  RESULT=$(curl -s "$NOMAD_ADDR/v1/jobs" -X POST \
    -d "{\"Job\":$PARSED}" \
    -H "Content-Type: application/json")
  echo "[OK] Deployed. $RESULT"
else
  echo "[ERROR] Parse failed: $PARSED"
  exit 1
fi
