param(
    [string]$DaprdBin = "",
    [string]$Tag      = "latest"
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

$LocalRegistry = "localhost:15000"
$ImageName     = "$LocalRegistry/daprd"

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
    Err "No daprd binary found. Place it in $ScriptDir or pass -DaprdBin path"
}

# --- 2. 在 WSL 中构建 Docker 镜像 ---
$wslScriptDir = wsl wslpath -u ($ScriptDir -replace '\\','/')
Info "Building Docker image: ${ImageName}:${Tag}"
wsl docker build -t "${ImageName}:${Tag}" $wslScriptDir
if ($LASTEXITCODE -ne 0) { Err "Docker build failed" }
Info "Docker build succeeded"

# --- 3. 推送到本地 registry ---
Info "Pushing ${ImageName}:${Tag} ..."
wsl docker push "${ImageName}:${Tag}"
if ($LASTEXITCODE -ne 0) { Err "Docker push failed" }

Info "=== Done: ${ImageName}:${Tag} pushed to local registry ==="
