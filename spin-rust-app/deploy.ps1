param([string]$Action = "deploy")

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$DeployDir = "/opt/spin-app"
$NomadAddr = "http://localhost:4646"

function Info($msg) { Write-Host "[INFO] $msg" -ForegroundColor Green }

if ($Action -eq "stop") {
    Info "stopping spin-app..."
    curl.exe -s -X DELETE "$NomadAddr/v1/job/spin-app?purge=true" | Out-Null
    Info "stopped"
    exit 0
}

# 1. build
Info "=== Build ==="
Push-Location $ScriptDir
E:\spin-v3.6.2-windows-amd64\spin.exe build
Pop-Location

# 2. deploy files to WSL
Info "=== Deploy files ==="
$wslPath = ($ScriptDir -replace '\\','/')
$driveLetter = $wslPath.Substring(0,1).ToLower()
$wslPath = "/mnt/$driveLetter" + $wslPath.Substring(2)
wsl bash -c "mkdir -p $DeployDir/target/wasm32-wasip1/release; cp '$wslPath/spin.toml' $DeployDir/; cp '$wslPath/target/wasm32-wasip1/release/spin_app.wasm' $DeployDir/target/wasm32-wasip1/release/"
Info "Files deployed"

# 2. submit nomad job via API
Info "=== Submit Nomad Job ==="
$hcl = [System.IO.File]::ReadAllText("$ScriptDir\spin-rust-app.nomad.hcl")
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
    # Force restart to pick up new wasm files
    curl.exe -s -X POST "$NomadAddr/v1/job/spin-app/evaluate?ForceReschedule=true" | Out-Null
    Info "Force restarted allocations"
} else {
    Write-Host "Deploy failed: $result" -ForegroundColor Red
    exit 1
}

Write-Host ""
Info "http://localhost:3500/v1.0/invoke/spin-app/method/health"
