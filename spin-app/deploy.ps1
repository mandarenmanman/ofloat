# 用法: .\deploy.ps1 <语言> [stop]
# 语言: go | rust | js | ts | python
# 示例: .\deploy.ps1 go        # 部署
#       .\deploy.ps1 ts stop   # 停止
param(
    [Parameter(Position=0, Mandatory=$true)]
    [ValidateSet("go", "rust", "js", "ts", "python")]
    [string]$Lang,
    [Parameter(Position=1)]
    [ValidateSet("deploy", "stop")]
    [string]$Action = "deploy"
)

$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$AppDir = Join-Path $RootDir $Lang
if (-not (Test-Path $AppDir)) {
    Write-Host "Language directory not found: $AppDir" -ForegroundColor Red
    exit 1
}

# Load env
$envFile = Join-Path (Split-Path $RootDir -Parent) ".env.ps1"
if (Test-Path $envFile) { . $envFile }

# App name
$AppName = "spin-$Lang-app"
if ($Lang -eq "rust") { $AppName = "spin-app" }
$ConfigVersion = Get-Date -Format "yyyyMMddHHmmss"
$ImageTag = "${AppName}:${ConfigVersion}"

# Memory config per language
$memConfig = @{
    "rust"   = @{ spin = 256;  spinMax = 512;  dapr = 256 }
    "go"     = @{ spin = 256;  spinMax = 512;  dapr = 256 }
    "js"     = @{ spin = 1024; spinMax = 4096; dapr = 512 }
    "ts"     = @{ spin = 512;  spinMax = 2048; dapr = 256 }
    "python" = @{ spin = 512;  spinMax = 2048; dapr = 256 }
}
$mem = $memConfig[$Lang]
if (-not $mem) {
    Write-Host "No memory config for language: $Lang" -ForegroundColor Red
    exit 1
}

function Info($msg) { Write-Host "[INFO] $msg" -ForegroundColor Green }

# --- Stop ---
if ($Action -eq "stop") {
    Info "stopping $AppName..."
    curl.exe -s -X DELETE "$NomadAddr/v1/job/${AppName}?purge=true" | Out-Null
    Info "stopped"
    exit 0
}

# --- Build ---
Info "=== Build ($Lang) ==="
Push-Location $AppDir

switch ($Lang) {
    "go" {
        $go123root = & go1.23.6 env GOROOT
        $env:GOROOT = $go123root
        $env:PATH = "$go123root\bin;$env:PATH"
        go mod tidy
        & $SpinExe build
    }
    "rust" {
        & $SpinExe build
    }
    "python" {
        if (-not (Test-Path "venv")) {
            Info "Creating virtual environment..."
            python -m venv venv
        }
        & "$AppDir\venv\Scripts\Activate.ps1"
        python -m pip install -r requirements.txt --quiet
        if ($LASTEXITCODE -ne 0) {
            Pop-Location
            Write-Host "pip install failed!" -ForegroundColor Red
            exit 1
        }
        & $SpinExe build
    }
    { $_ -in "js", "ts" } {
        npm install
        npm run build
    }
    default {
        Pop-Location
        Write-Host "Unknown language: $Lang" -ForegroundColor Red
        exit 1
    }
}

if ($LASTEXITCODE -ne 0) {
    Pop-Location
    Write-Host "Build failed!" -ForegroundColor Red
    exit 1
}
Pop-Location

# --- Push to local registry ---
Info "=== Push to $Registry ==="
Push-Location $AppDir
& $SpinExe registry push "$Registry/${ImageTag}" --insecure
Pop-Location
Info "Pushed to $Registry/${ImageTag}"

# --- Generate HCL from template ---
Info "=== Generate Nomad Job HCL ==="
$tplFile = Join-Path $RootDir "spin-app.nomad.hcl"
$hcl = [System.IO.File]::ReadAllText($tplFile)
$hcl = $hcl.Replace("<<APP_NAME>>", $AppName)
$hcl = $hcl.Replace("<<IMAGE_TAG>>", $ImageTag)
$hcl = $hcl.Replace("<<CONFIG_VERSION>>", $ConfigVersion)
$hcl = $hcl.Replace("<<SPIN_MEMORY>>", "$($mem.spin)")
$hcl = $hcl.Replace("<<SPIN_MEMORY_MAX>>", "$($mem.spinMax)")
$hcl = $hcl.Replace("<<DAPR_MEMORY>>", "$($mem.dapr)")

# --- Submit Nomad Job ---
Info "=== Submit Nomad Job ==="
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
    curl.exe -s -X POST "$NomadAddr/v1/job/${AppName}/evaluate?ForceReschedule=true" | Out-Null
    Info "Force restarted allocations"
} else {
    Write-Host "Deploy failed: $result" -ForegroundColor Red
    exit 1
}

Write-Host ""
Info "Traefik: http://localhost/${AppName}/health  (image: ${ImageTag})"
