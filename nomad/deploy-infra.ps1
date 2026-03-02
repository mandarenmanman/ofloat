param([string]$Action = "deploy")
$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$envFile = Join-Path (Split-Path $ScriptDir -Parent) ".env.ps1"
if (Test-Path $envFile) { . $envFile }
if (-not $NomadAddr) { $NomadAddr = "http://localhost:4646" }

$Jobs = @(
    @{ Name = "redis";           File = "redis.nomad.hcl" },
    @{ Name = "dapr-placement";  File = "dapr-placement.nomad.hcl" },
    @{ Name = "registry";        File = "registry.nomad.hcl" }
)

function Info($msg)  { Write-Host "[INFO] $msg" -ForegroundColor Green }
function Warn($msg)  { Write-Host "[WARN] $msg" -ForegroundColor Yellow }
function Err($msg)   { Write-Host "[ERR]  $msg" -ForegroundColor Red }

function Deploy-Job($jobName, $hclFile) {
    $hclPath = Join-Path $ScriptDir $hclFile
    if (-not (Test-Path $hclPath)) {
        Err "$hclFile not found, skipping"
        return $false
    }

    Info "Deploying $jobName ..."
    $hcl = [System.IO.File]::ReadAllText($hclPath)
    $escaped = ($hcl | ConvertTo-Json)
    $parseBody = '{"JobHCL":' + $escaped + ',"Canonicalize":true}'

    $tmpParse  = [System.IO.Path]::GetTempFileName()
    $tmpSubmit = [System.IO.Path]::GetTempFileName()

    try {
        [System.IO.File]::WriteAllBytes($tmpParse, [System.Text.Encoding]::UTF8.GetBytes($parseBody))
        curl.exe -s -X POST "$NomadAddr/v1/jobs/parse" -H "Content-Type: application/json" -d "@$tmpParse" -o $tmpSubmit

        $job = [System.IO.File]::ReadAllText($tmpSubmit)
        $envelope = '{"Job":' + $job + '}'
        [System.IO.File]::WriteAllBytes($tmpSubmit, [System.Text.Encoding]::UTF8.GetBytes($envelope))
        $result = curl.exe -s -X POST "$NomadAddr/v1/jobs" -H "Content-Type: application/json" -d "@$tmpSubmit" | ConvertFrom-Json

        if ($result.EvalID) {
            Info "$jobName deployed, EvalID: $($result.EvalID)"
            return $true
        } else {
            Err "$jobName deploy failed: $result"
            return $false
        }
    } finally {
        Remove-Item $tmpParse, $tmpSubmit -ErrorAction SilentlyContinue
    }
}

function Stop-Job($jobName) {
    Info "Stopping $jobName ..."
    $resp = curl.exe -s -X DELETE "$NomadAddr/v1/job/$jobName`?purge=true"
    Info "$jobName stopped"
}

# --- main ---
if ($Action -eq "stop") {
    foreach ($j in $Jobs) { Stop-Job $j.Name }
    Info "All infrastructure jobs stopped."
    exit 0
}

if ($Action -eq "status") {
    foreach ($j in $Jobs) {
        $resp = curl.exe -s "$NomadAddr/v1/job/$($j.Name)" | ConvertFrom-Json 2>$null
        if ($resp.ID) {
            Info "$($j.Name): Status=$($resp.Status)"
        } else {
            Warn "$($j.Name): not found"
        }
    }
    exit 0
}

# deploy
$success = 0
$failed  = 0
foreach ($j in $Jobs) {
    if (Deploy-Job $j.Name $j.File) { $success++ } else { $failed++ }
}

Write-Host ""
Info "=== Done: $success deployed, $failed failed ==="

# verify
Write-Host ""
Info "Verifying services (waiting 5s for startup) ..."
Start-Sleep -Seconds 5
foreach ($j in $Jobs) {
    $resp = curl.exe -s "$NomadAddr/v1/job/$($j.Name)/allocations" | ConvertFrom-Json 2>$null
    if ($resp -and $resp.Count -gt 0) {
        $latest = $resp[0]
        Info "$($j.Name): ClientStatus=$($latest.ClientStatus)"
    } else {
        Warn "$($j.Name): no allocations found"
    }
}
