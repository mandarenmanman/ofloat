param([string]$Action = "deploy")
$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$envFile = Join-Path (Split-Path $ScriptDir -Parent) ".env.ps1"
if (Test-Path $envFile) { . $envFile }
if (-not $NomadAddr) { $NomadAddr = "http://localhost:4646" }
if (-not $DufsAddr) { $DufsAddr = "http://localhost:5555" }

function Info($msg) { Write-Host "[INFO] $msg" -ForegroundColor Green }

if ($Action -eq "stop") {
    Info "stopping dapr-bindings..."
    curl.exe -s -X DELETE "$NomadAddr/v1/job/dapr-bindings?purge=true" | Out-Null
    Info "stopped"
    exit 0
}

# 1. Build WASM — standard WASI program (GOOS=wasip1 GOARCH=wasm)
Info "=== Build ==="
$go123root = & go1.23.6 env GOROOT
$env:GOROOT = $go123root
$env:PATH = "$go123root\bin;$env:PATH"
Push-Location $ScriptDir
go mod tidy
$env:GOOS = "wasip1"
$env:GOARCH = "wasm"
go build -o bindings.wasm .
if ($LASTEXITCODE -ne 0) {
    Pop-Location
    Write-Host "Build failed!" -ForegroundColor Red
    exit 1
}
Remove-Item Env:\GOOS
Remove-Item Env:\GOARCH
Pop-Location
Info "Built bindings.wasm"

# 2. Upload WASM to dufs file server
Info "=== Upload to dufs ==="
$wslPath = $ScriptDir -replace '\\','/'
$wslPath = $wslPath -replace '^([A-Za-z]):','/mnt/$1'
$wslPath = $wslPath.ToLower().Substring(0,6) + $wslPath.Substring(6)
wsl curl -s -T "$wslPath/bindings.wasm" $DufsAddr/bindings.wasm
Info "Uploaded bindings.wasm to dufs"

# 3. Submit Nomad Job via API
Info "=== Submit Nomad Job ==="
$hcl = [System.IO.File]::ReadAllText("$ScriptDir\dapr-bindings.nomad.hcl")
$escaped = ($hcl | ConvertTo-Json)
$parseBody = '{"JobHCL":' + $escaped + ',"Canonicalize":true}'
$tmpParse = [System.IO.Path]::GetTempFileName()
$tmpSubmit = [System.IO.Path]::GetTempFileName()

[System.IO.File]::WriteAllBytes($tmpParse, [System.Text.Encoding]::UTF8.GetBytes($parseBody))
curl.exe -s -X POST "$NomadAddr/v1/jobs/parse" -H "Content-Type: application/json" -d "@$tmpParse" -o $tmpSubmit

$job = [System.IO.File]::ReadAllText($tmpSubmit)
$envelope = '{"Job":' + $job + '}'
[System.IO.File]::WriteAllBytes($tmpSubmit, [System.Text.Encoding]::UTF8.GetBytes($envelope))
$result = curl.exe -s -X POST "$NomadAddr/v1/jobs" -H "Content-Type: application/json" -d "@$tmpSubmit" | ConvertFrom-Json

Remove-Item $tmpParse, $tmpSubmit -ErrorAction SilentlyContinue

if ($result.EvalID) {
    Info "Deployed! EvalID: $($result.EvalID)"
    curl.exe -s -X POST "$NomadAddr/v1/job/dapr-bindings/evaluate?ForceReschedule=true" | Out-Null
    Info "Force restarted allocations"
} else {
    Write-Host "Deploy failed: $result" -ForegroundColor Red
    exit 1
}

Write-Host ""
Info "Verify (from WSL):"
Info "  wsl curl -s -X POST http://localhost:3519/v1.0/bindings/wasm -H 'Content-Type: application/json' -d '{\"operation\":\"execute\",\"data\":\"{\\\"action\\\":\\\"health\\\"}\"}'  "
