#!/bin/bash
# Start Nomad (server + client combined, single-node)
# Usage: sudo bash start-server.sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$(dirname "$SCRIPT_DIR")/.env.sh"

# Stop ALL existing Nomad agent processes (including -dev mode)
NOMAD_PIDS=$(pgrep -x nomad || true)
if [ -n "$NOMAD_PIDS" ]; then
    echo "[INFO] Stopping existing Nomad processes: $NOMAD_PIDS"
    kill $NOMAD_PIDS 2>/dev/null || true
    sleep 3
fi

mkdir -p /opt/nomad/data

echo "[INFO] Starting Nomad (server+client) with Consul at 127.0.0.1:8500..."
nomad agent -config=/etc/nomad.d/server.hcl &

echo "[INFO] Nomad started (PID: $!)"
echo "[INFO] Waiting for leader election..."
sleep 5

if curl -s ${NOMAD_ADDR}/v1/status/leader | grep -q ':'; then
    echo "[INFO] Nomad server is ready. Leader: $(curl -s ${NOMAD_ADDR}/v1/status/leader)"
else
    echo "[WARN] Nomad may still be starting. Check: curl ${NOMAD_ADDR}/v1/status/leader"
fi

# Verify Consul registration
sleep 2
if curl -s http://127.0.0.1:8500/v1/catalog/service/nomad | grep -q 'ServiceName'; then
    echo "[INFO] Nomad registered in Consul."
else
    echo "[WARN] Nomad not yet visible in Consul."
fi
