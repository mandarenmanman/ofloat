#!/bin/bash
set -e

# =============================================================================
# Nomad 部署脚本
# 部署 Spin WASM (exec driver) + Dapr Sidecar (docker driver)
#
# 前提: redis, dapr-placement 已在 Nomad 中运行
#
# 用法:
#   bash deploy-nomad.sh          # 构建并部署应用
#   bash deploy-nomad.sh stop     # 停止全部服务（含基础设施）
#   bash deploy-nomad.sh app-only # 只重新部署 spin-app（跳过构建）
# =============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPIN_APP_DIR="/opt/spin-app"

# 停止模式
if [[ "$1" == "stop" ]]; then
  info "停止所有 Nomad jobs..."
  nomad job stop -purge spin-app 2>/dev/null || true
  nomad job stop -purge dapr-placement 2>/dev/null || true
  nomad job stop -purge dapr-dashboard 2>/dev/null || true
  nomad job stop -purge redis 2>/dev/null || true
  nomad job stop -purge registry 2>/dev/null || true
  info "全部已停止 ✓"
  exit 0
fi

# 部署 Spin 应用文件到 /opt/spin-app
deploy_spin_files() {
  info "部署 Spin 应用文件到 ${SPIN_APP_DIR}..."
  mkdir -p "${SPIN_APP_DIR}/target/wasm32-wasip1/release"
  cp "${SCRIPT_DIR}/spin-app/spin.toml" "${SPIN_APP_DIR}/"
  cp "${SCRIPT_DIR}/spin-app/target/wasm32-wasip1/release/spin_app.wasm" \
     "${SPIN_APP_DIR}/target/wasm32-wasip1/release/"
  cp "${SCRIPT_DIR}/spin-app/run.sh" "${SPIN_APP_DIR}/"
  chmod +x "${SPIN_APP_DIR}/run.sh"
  info "文件部署完成 ✓"
}

# 只部署应用（跳过构建）
if [[ "$1" == "app-only" ]]; then
  deploy_spin_files
  nomad job run "${SCRIPT_DIR}/nomad/spin-app.nomad.hcl"
  sleep 3
  nomad job status spin-app
  exit 0
fi

# ---------------------------------------------------------------------------
# 1. 构建 Spin 应用
# ---------------------------------------------------------------------------
info "=== Step 1/2: 构建 Spin 应用 ==="

if command -v spin &>/dev/null && command -v cargo &>/dev/null; then
  cd "${SCRIPT_DIR}/spin-app"
  spin build
  cd "${SCRIPT_DIR}"
else
  warn "spin/cargo 未安装，跳过 WASM 编译（使用已有的 wasm 文件）"
fi

if [[ ! -f "${SCRIPT_DIR}/spin-app/target/wasm32-wasip1/release/spin_app.wasm" ]]; then
  error "找不到 spin_app.wasm，请先编译: cd spin-app && spin build"
fi

deploy_spin_files

# ---------------------------------------------------------------------------
# 2. 部署应用
# ---------------------------------------------------------------------------
info "=== Step 2/2: 部署 Spin + Dapr ==="

nomad job run "${SCRIPT_DIR}/nomad/spin-app.nomad.hcl"
nomad job run "${SCRIPT_DIR}/nomad/dapr-dashboard.nomad.hcl"

sleep 3
nomad job status spin-app

echo ""
echo "============================================="
info "🎉 部署完成！"
echo "============================================="
echo ""
echo "  🔗 应用访问（通过 Dapr）: http://localhost:3500/v1.0/invoke/spin-app/method/"
echo "  📊 Dapr Dashboard:       http://localhost:8080"
echo "  📈 Nomad UI:             http://localhost:4646"
echo ""
echo "  curl http://localhost:3500/v1.0/invoke/spin-app/method/health"
echo ""
