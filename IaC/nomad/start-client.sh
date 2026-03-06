#!/bin/bash
# Start Nomad client
# Usage: sudo bash start-client.sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$(dirname "$SCRIPT_DIR")/.env.sh"

NOMAD_PID=$(pgrep -f 'nomad agent.*client' || true)
if [ -n "$NOMAD_PID" ]; then
    echo "[INFO] Stopping existing Nomad client (PID: $NOMAD_PID)..."
    kill "$NOMAD_PID"
    sleep 2
fi

echo "[INFO] Starting Nomad client..."
nomad agent -config=/etc/nomad.d/client.hcl &

echo "[INFO] Nomad client started (PID: $!)"
sleep 3

if nomad node status 2>/dev/null | grep -q 'ready'; then
    echo "[INFO] Nomad client is ready."
else
    echo "[WARN] Nomad client may still be starting."
fi
