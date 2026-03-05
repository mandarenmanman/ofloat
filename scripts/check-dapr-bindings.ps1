# 诊断 dapr-bindings 通过 Traefik 的访问（PowerShell，本地请求）
# 用法: .\scripts\check-dapr-bindings.ps1

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
if ($Host.UI.RawUI) { try { $Host.UI.RawUI.CodePage = 65001 } catch {} }
$ErrorActionPreference = "Continue"
$base = "http://127.0.0.1"

function Show-Err($e) {
    if ($e.Exception.Response) {
        $code = [int]$e.Exception.Response.StatusCode
        $reader = New-Object System.IO.StreamReader($e.Exception.Response.GetResponseStream())
        $reader.BaseStream.Position = 0
        Write-Host "  HTTP $code $($reader.ReadToEnd())" -ForegroundColor Red
    } else {
        Write-Host "  $($e.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host "=== 1. 测试本地 :80 (Traefik) ===" -ForegroundColor Cyan
try {
    $r = Invoke-WebRequest -Uri "$base/" -UseBasicParsing -TimeoutSec 3
    Write-Host "  HTTP $($r.StatusCode) Traefik 可达" -ForegroundColor Green
} catch {
    if ($_.Exception.Response) {
        $code = [int]$_.Exception.Response.StatusCode
        if ($code -eq 404) {
            Write-Host "  HTTP 404 (根路径无路由，属正常) Traefik 可达" -ForegroundColor Green
        } else {
            Write-Host "  HTTP $code" -ForegroundColor Red
        }
    } else {
        Write-Host "  连接失败: $($_.Exception.Message)" -ForegroundColor Red
    }
}

$uri = "$base/dapr-bindings/v1.0/bindings/wasm"
$headers = @{
    "Content-Type" = "application/json"
    "dapr-app-id" = "dapr-bindings"
}

Write-Host "`n=== 2. 健康检查 (health) ===" -ForegroundColor Cyan
$body = '{"operation":"execute","data":"{\"action\":\"health\"}"}'
try {
    $r = Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body $body -TimeoutSec 5
    Write-Host "  响应: $($r | ConvertTo-Json -Compress)" -ForegroundColor Green
} catch { Show-Err $_ }

Write-Host "`n=== 3. 存入 state (save-state) ===" -ForegroundColor Cyan
$inner = '{"action":"save-state","data":{"key":"test-key","value":"hello-from-ps"}}'
$body = @{ operation = "execute"; data = $inner } | ConvertTo-Json -Compress
try {
    $r = Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body $body -TimeoutSec 5
    Write-Host "  响应: $($r | ConvertTo-Json -Compress)" -ForegroundColor Green
} catch { Show-Err $_ }

Write-Host "`n=== 4. 取出 state (get-state) ===" -ForegroundColor Cyan
$inner = '{"action":"get-state","data":{"key":"test-key"}}'
$body = @{ operation = "execute"; data = $inner } | ConvertTo-Json -Compress
try {
    $r = Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body $body -TimeoutSec 5
    Write-Host "  响应: $($r | ConvertTo-Json -Compress)" -ForegroundColor Green
    if ($r.result.value -eq "hello-from-ps") { Write-Host "  OK (value match)" -ForegroundColor Green } else { Write-Host "  WARN value:" $r.result.value -ForegroundColor Yellow }
} catch { Show-Err $_ }

Write-Host ""
