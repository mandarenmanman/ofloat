param([string]$Action = "deploy")

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$GhcrUser = ""
$GhcrToken = ""
$envFile = Join-Path (Split-Path $ScriptDir -Parent) ".env.ps1"
if (Test-Path $envFile) { . $envFile }
$ImageTag = "order-service2:latest"

function Info($msg) { Write-Host "[INFO] $msg" -ForegroundColor Green }

if ($Action -eq "stop") {
    Info "stopping order-service2..."
    curl.exe -s -X DELETE "$NomadAddr/v1/job/order-service2?purge=true" | Out-Null
    Info "stopped"
    exit 0
}

# 1. build
Info "=== Build ==="
Push-Location $ScriptDir
npm run build
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
$hcl = [System.IO.File]::ReadAllText("$ScriptDir\order-service2.nomad.hcl")
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
    curl.exe -s -X POST "$NomadAddr/v1/job/order-service2/evaluate?ForceReschedule=true" | Out-Null
    Info "Force restarted allocations"
} else {
    Write-Host "Deploy failed: $result" -ForegroundColor Red
    exit 1
}

Write-Host ""
Info "http://localhost:3503/v1.0/invoke/order-service2/method/health"
