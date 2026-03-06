#!/bin/bash
# Install Nomad configuration and prerequisites
# Usage: sudo bash install.sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$(dirname "$SCRIPT_DIR")/.env.sh"

echo "[INFO] Installing Nomad configuration..."

# 1. Copy configs
mkdir -p /etc/nomad.d
cp -f "$SCRIPT_DIR/server.hcl" /etc/nomad.d/server.hcl
cp -f "$SCRIPT_DIR/client.hcl" /etc/nomad.d/client.hcl
rm -f /etc/nomad.d/nomad.hcl
echo "[INFO] Copied server.hcl, client.hcl -> /etc/nomad.d/"

# 2. Switch iptables to legacy (required for bridge network mode on nftables kernels)
update-alternatives --set iptables /usr/sbin/iptables-legacy 2>/dev/null || true
update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy 2>/dev/null || true
echo "[INFO] iptables set to legacy: $(iptables --version)"

# 3. Ensure pause image exists in local registry
if docker image inspect "${PAUSE_IMAGE}" >/dev/null 2>&1; then
    echo "[INFO] ${PAUSE_IMAGE} already exists"
elif docker image inspect registry.k8s.io/pause-amd64:3.3 >/dev/null 2>&1; then
    docker tag registry.k8s.io/pause-amd64:3.3 "${PAUSE_IMAGE}"
    docker push "${PAUSE_IMAGE}"
    echo "[INFO] Tagged and pushed ${PAUSE_IMAGE}"
elif docker image inspect registry.aliyuncs.com/google_containers/pause-amd64:3.3 >/dev/null 2>&1; then
    docker tag registry.aliyuncs.com/google_containers/pause-amd64:3.3 "${PAUSE_IMAGE}"
    docker push "${PAUSE_IMAGE}"
    echo "[INFO] Tagged and pushed ${PAUSE_IMAGE}"
else
    echo "[WARN] pause-amd64:3.3 not found locally. Pull it first:"
    echo "  docker pull registry.aliyuncs.com/google_containers/pause-amd64:3.3"
fi

echo "[INFO] Install complete. Run start-server.sh and start-client.sh to start Nomad."
