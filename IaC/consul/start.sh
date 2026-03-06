#!/bin/bash
# Start Consul agent
# Usage: sudo bash start.sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$(dirname "$SCRIPT_DIR")/.env.sh"

# Stop existing Consul if running
CONSUL_PID=$(pgrep -f 'consul agent' || true)
if [ -n "$CONSUL_PID" ]; then
    echo "[INFO] Stopping existing Consul agent (PID: $CONSUL_PID)..."
    kill "$CONSUL_PID"
    sleep 2
fi

echo "[INFO] Starting Consul agent..."
consul agent -config-dir=/etc/consul.d/ &

echo "[INFO] Consul agent started (PID: $!)"
sleep 3

if curl -s http://${CONSUL_ADDR}/v1/status/leader | grep -q ':'; then
    echo "[INFO] Consul is ready."
    echo "[INFO] UI: http://${CONSUL_ADDR}"
else
    echo "[WARN] Consul may still be starting. Check: curl http://${CONSUL_ADDR}/v1/status/leader"
fi
