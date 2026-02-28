# 部署 order-service2 到 Nomad

$IMAGE_NAME = "ghcr.io/mandarenmanman/order-service2"
$TAG = "latest"

Write-Host "🔨 构建 WASM 模块..."
spin build

Write-Host "📦 推送到容器 registry..."
# 需要根据实际情况调整推送命令
# spin registry push $IMAGE_NAME:$TAG

Write-Host "🚀 部署到 Nomad..."
nomad job run order-service2.nomad.hcl

Write-Host "✅ 部署完成!"
Write-Host "📍 服务地址：http://localhost:8082"
Write-Host ""
Write-Host "API 端点:"
Write-Host "  GET    /health          - 健康检查"
Write-Host "  GET    /orders          - 获取所有订单"
Write-Host "  GET    /orders/:id      - 获取单个订单"
Write-Host "  POST   /orders          - 创建订单"
Write-Host "  PUT    /orders/:id      - 更新订单"
Write-Host "  DELETE /orders/:id      - 删除订单"
