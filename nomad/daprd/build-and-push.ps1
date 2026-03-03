param(
    [string]$DaprdBin = "",
    [string]$Tag      = "latest"
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$envFile   = Join-Path (Split-Path (Split-Path $ScriptDir -Parent) -Parent) ".env.ps1"
if (Test-Path $envFile) { . $envFile }

$ImageName = "$Registry/daprd"

function Info($msg)  { Write-Host "[INFO] $msg" -ForegroundColor Green }
function Err($msg)   { Write-Host "[ERR]  $msg" -ForegroundColor Red; exit 1 }

# --- 1. 确定 daprd 二进制来源 ---
$localBin = Join-Path $ScriptDir "daprd"

if ($DaprdBin) {
    Copy-Item $DaprdBin $localBin -Force
    Info "Copied daprd from $DaprdBin"
} elseif (Test-Path $localBin) {
    Info "Using existing daprd in $ScriptDir"
} else {
    # fallback：从 WSL 中复制编译产物
    $wslPath = "/tmp/dapr/dist/linux_amd64/release/daprd"
    Info "Copying daprd from WSL: $wslPath"
    wsl cp $wslPath /mnt/$(($ScriptDir -replace '\\','/') -replace '^(\w):','$1' | ForEach-Object { $_.Substring(0,1).ToLower() + $_.Substring(1) })/daprd 2>$null
    if (-not (Test-Path $localBin)) { Err "Failed to copy daprd from WSL" }
    Info "Copied daprd from WSL"
}

# --- 2. 在 WSL 中构建 Docker 镜像 ---
$wslScriptDir = wsl wslpath -u ($ScriptDir -replace '\\','/')
Info "Building Docker image: ${ImageName}:${Tag}"
wsl docker build -t "${ImageName}:${Tag}" $wslScriptDir
if ($LASTEXITCODE -ne 0) { Err "Docker build failed" }
Info "Docker build succeeded"

# --- 3. 登录 ghcr.io 并推送 ---
Info "Logging in to ghcr.io ..."
wsl bash -c "echo '$GhcrToken' | docker login ghcr.io -u $GhcrUser --password-stdin"
if ($LASTEXITCODE -ne 0) { Err "Docker login failed" }

Info "Pushing ${ImageName}:${Tag} ..."
wsl docker push "${ImageName}:${Tag}"
if ($LASTEXITCODE -ne 0) { Err "Docker push failed" }

Info "=== Done: ${ImageName}:${Tag} pushed ==="

# --- 4. 清理本地 daprd 二进制 ---
$localBin = Join-Path $ScriptDir "daprd"
if (Test-Path $localBin) { Remove-Item $localBin -Force }
Info "Cleaned up local daprd binary"
