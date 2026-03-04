#!/bin/bash
# Install Consul binary and configuration
# Usage: sudo bash install.sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$(dirname "$SCRIPT_DIR")/.env.sh"

ARCH="amd64"

echo "[INFO] Installing Consul ${CONSUL_VERSION}..."

# 1. Check existing installation
NEED_INSTALL=true
if command -v consul &>/dev/null; then
    CURRENT=$(consul version | head -1 | grep -oP 'v\K[0-9.]+')
    if [ "$CURRENT" = "$CONSUL_VERSION" ]; then
        echo "[INFO] Consul v${CURRENT} already installed, skipping."
        NEED_INSTALL=false
    else
        echo "[INFO] Consul version mismatch: v${CURRENT} -> v${CONSUL_VERSION}"
        echo "[INFO] Removing old binary..."
        rm -f "$(which consul)"
    fi
fi

# 2. Download and install
if [ "$NEED_INSTALL" = true ]; then
    TMPDIR=$(mktemp -d)
    cd "$TMPDIR"
    echo "[INFO] Downloading consul_${CONSUL_VERSION}_linux_${ARCH}.zip..."
    wget -q "https://releases.hashicorp.com/consul/${CONSUL_VERSION}/consul_${CONSUL_VERSION}_linux_${ARCH}.zip"
    unzip -q "consul_${CONSUL_VERSION}_linux_${ARCH}.zip"
    mv consul /usr/local/bin/consul
    chmod +x /usr/local/bin/consul
    rm -rf "$TMPDIR"
    echo "[INFO] Consul installed: $(consul version | head -1)"
fi

# 3. Copy configuration (substitute variables from .env.sh)
mkdir -p /etc/consul.d
mkdir -p /opt/consul/data
export CONSUL_BIND
envsubst '${CONSUL_BIND}' < "$SCRIPT_DIR/consul.hcl" > /etc/consul.d/consul.hcl
echo "[INFO] Copied consul.hcl -> /etc/consul.d/consul.hcl (bind=${CONSUL_BIND})"

echo "[INFO] Install complete. Run start.sh to start Consul."
echo "[INFO] UI will be available at http://${CONSUL_ADDR}"
