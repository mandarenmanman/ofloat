param([string]$Action = "deploy")
$env:GOROOT = $(go1.23.6 env GOROOT)
$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$SpinExe = "E:\spin-v3.6.2-windows-amd64\spin.exe"
$GhcrUser = ""
$GhcrToken = ""
$envFile = Join-Path (Split-Path $ScriptDir -Parent) ".env.ps1"
if (Test-Path $envFile) { . $envFile }
$Registry = "ghcr.io/mandarenmanman"
$ImageTag = "spin-payment6-service:latest"
$NomadAddr = "http://localhost:4646"

function Info($msg) { Write-Host "[INFO] $msg" -ForegroundColor Green }

if ($Action -eq "stop") {
    Info "stopping spin-payment6-service..."
    curl.exe -s -X DELETE "$NomadAddr/v1/job/spin-payment6-service?purge=true" | Out-Null
    Info "stopped"
    exit 0
}

# 1. build
Info "=== Build ==="
$go123root = & go1.23.6 env GOROOT
$env:GOROOT = $go123root
$env:PATH = "$go123root\bin;$env:PATH"
Push-Location $ScriptDir
go mod tidy
& $SpinExe build
if ($LASTEXITCODE -ne 0) {
    Pop-Location
    Write-Host "Build failed!" -ForegroundColor Red
    exit 1
}
Pop-Location

# 2. login & push to ghcr.io
Info "=== Push to ghcr.io ==="
& $SpinExe registry login ghcr.io -u $GhcrUser -p $GhcrToken
Push-Location $ScriptDir
& $SpinExe registry push "$Registry/${ImageTag}"
Pop-Location
Info "Pushed to $Registry/${ImageTag}"

# 3. submit nomad job via API
Info "=== Submit Nomad Job ==="
$hcl = [System.IO.File]::ReadAllText("$ScriptDir\spin-payment6-service.nomad.hcl")
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
    curl.exe -s -X POST "$NomadAddr/v1/job/spin-payment6-service/evaluate?ForceReschedule=true" | Out-Null
    Info "Force restarted allocations"
} else {
    Write-Host "Deploy failed: $result" -ForegroundColor Red
    exit 1
}

Write-Host ""
Info "http://localhost:3513/v1.0/invoke/spin-payment6-service/method/health"
