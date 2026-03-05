# 用法: .\deploy.ps1 <语言> [stop]
# 语言: go | rust | c | cpp | ts | assemblyscript
# 示例: .\deploy.ps1 go        # 部署
#       .\deploy.ps1 rust stop # 停止
param(
    [Parameter(Position=0, Mandatory=$true)]
    [ValidateSet("go", "rust", "c", "cpp", "ts", "assemblyscript")]
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
if (-not $NomadAddr) { $NomadAddr = "http://localhost:4646" }
if (-not $DufsAddr) { $DufsAddr = "http://localhost:5555" }

$AppName = "dapr-bindings"
$WasmFile = "bindings.wasm"
$DaprMemory = 256

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
$BuildDir = Join-Path $AppDir "build"
if (-not (Test-Path $BuildDir)) { New-Item -ItemType Directory -Path $BuildDir | Out-Null }
Push-Location $AppDir

switch ($Lang) {
    "go" {
        $go123root = & go1.23.6 env GOROOT
        $env:GOROOT = $go123root
        $env:PATH = "$go123root\bin;$env:PATH"
        go mod tidy
        $env:GOOS = "wasip1"
        $env:GOARCH = "wasm"
        go build -o "$BuildDir\$WasmFile" .
        Remove-Item Env:\GOOS
        Remove-Item Env:\GOARCH
    }
    "rust" {
        cargo build --release --target wasm32-wasip1
        Copy-Item "target\wasm32-wasip1\release\*.wasm" "$BuildDir\$WasmFile"
    }
    "c" {
        make clean; make
    }
    "cpp" {
        make clean; make
    }
    "ts" {
        npm install
        npm run build
    }
    "assemblyscript" {
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
Info "Built build/$WasmFile"

# --- Upload to dufs ---
Info "=== Upload to dufs ==="
$wslPath = $BuildDir -replace '\\','/'
$wslPath = $wslPath -replace '^([A-Za-z]):','/mnt/$1'
$wslPath = $wslPath.ToLower().Substring(0,6) + $wslPath.Substring(6)
wsl curl -s -T "$wslPath/$WasmFile" $DufsAddr/$WasmFile
Info "Uploaded $WasmFile to dufs"

# --- Generate HCL from template ---
Info "=== Generate Nomad Job HCL ==="
$tplFile = Join-Path $RootDir "dapr-bindings.nomad.hcl"
$hcl = [System.IO.File]::ReadAllText($tplFile)
$hcl = $hcl.Replace("<<APP_NAME>>", $AppName)
$hcl = $hcl.Replace("<<WASM_FILE>>", $WasmFile)
$hcl = $hcl.Replace("<<DAPR_MEMORY>>", "$DaprMemory")

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
Info "Traefik: http://localhost/${AppName}/v1.0/bindings/wasm"
