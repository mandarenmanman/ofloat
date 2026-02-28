#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="/opt/spin-js-app"

info() { echo -e "\033[0;32m[INFO]\033[0m $1"; }

if [[ "$1" == "stop" ]]; then
  info "停止 spin-js-app..."
  nomad job stop -purge spin-js-app 2>/dev/null || true
  info "已停止 ✓"
  exit 0
fi

info "=== 部署 Spin JS App ==="

mkdir -p "${DEPLOY_DIR}/dist"
cp "${SCRIPT_DIR}/spin.toml" "${DEPLOY_DIR}/"
cp "${SCRIPT_DIR}/dist/spin-js-app.wasm" "${DEPLOY_DIR}/dist/"

info "文件部署到 ${DEPLOY_DIR} ✓"

nomad job run "${SCRIPT_DIR}/spin-js-app.nomad.hcl"

sleep 3
nomad job status spin-js-app

echo ""
info "🎉 部署完成！"
echo "  🔗 http://localhost:3501/v1.0/invoke/spin-js-app/method/health"
echo ""
