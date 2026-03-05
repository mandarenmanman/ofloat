#!/bin/bash
set -e

# Install WASI SDK
WASI_SDK_VERSION="25"
WASI_SDK_DIR="/opt/wasi-sdk"

if [ ! -d "$WASI_SDK_DIR" ]; then
  echo "[INFO] Installing wasi-sdk ${WASI_SDK_VERSION}..."
  curl -fsSL "https://github.com/aspect-build/aspect-cli/releases/download/wasi-sdk-${WASI_SDK_VERSION}/wasi-sdk-${WASI_SDK_VERSION}.0-x86_64-linux.tar.gz" \
    | sudo tar xz -C /opt
  sudo ln -sf "/opt/wasi-sdk-${WASI_SDK_VERSION}.0-x86_64-linux" "$WASI_SDK_DIR"
fi

echo "[INFO] wasi-sdk ready at $WASI_SDK_DIR"
echo "export WASI_SDK_PATH=$WASI_SDK_DIR" >> ~/.bashrc
