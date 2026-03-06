#!/bin/bash
set -e
NOMAD_ADDR="http://localhost:4646"
BASE="/mnt/d/github/ofloat"

deploy_job() {
  local job_file="$1"
  local job_name="$2"
  echo "[INFO] Deploying $job_name from $job_file..."
  JOB_HCL=$(cat "$job_file")
  PARSED=$(curl -s "$NOMAD_ADDR/v1/jobs/parse" -X POST \
    -d "{\"JobHCL\":$(python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" <<< "$JOB_HCL")}" \
    -H "Content-Type: application/json")
  if echo "$PARSED" | grep -q '"ID"'; then
    RESULT=$(curl -s "$NOMAD_ADDR/v1/jobs" -X POST \
      -d "{\"Job\":$PARSED}" \
      -H "Content-Type: application/json")
    echo "[OK] $job_name deployed."
  else
    echo "[ERROR] $job_name parse failed: $PARSED"
    return 1
  fi
}

# 1. Registry first
deploy_job "$BASE/nomad/registry.nomad.hcl" "registry"

# 2. Wait for registry to be ready
echo "[INFO] Waiting for registry on port 15000..."
for i in $(seq 1 30); do
  if curl -s http://localhost:15000/v2/ >/dev/null 2>&1; then
    echo "[OK] Registry is ready."
    break
  fi
  sleep 2
done

# 3. Push traefik image to local registry
echo "[INFO] Tagging and pushing traefik to local registry..."
docker tag n5nsx2pw56rzh4.xuanyuan.run/library/traefik:v3.4 localhost:15000/traefik:v3.4 2>/dev/null || true
docker push localhost:15000/traefik:v3.4

# 4. Deploy other infra jobs
deploy_job "$BASE/nomad/redis.nomad.hcl" "redis"
deploy_job "$BASE/nomad/dapr-placement.nomad.hcl" "dapr-placement"
deploy_job "$BASE/traefik/traefik.nomad.hcl" "traefik"

echo ""
echo "[INFO] All infra jobs deployed. Checking status..."
sleep 5
curl -s "$NOMAD_ADDR/v1/jobs" | python3 -c '
import sys,json
for j in json.load(sys.stdin):
    print("  %-20s %s" % (j["ID"], j["Status"]))
'
