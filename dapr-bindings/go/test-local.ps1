# Test bindings.wasm locally using Docker daprd (Linux)
# Windows daprd does NOT support bindings.wasm (stealthrocket/wasi-go doesn't compile on Windows)
# Usage: .\test-local.ps1
$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$envFile = Join-Path (Split-Path $ScriptDir -Parent) ".env.ps1"
if (Test-Path $envFile) { . $envFile }
if (-not $DufsAddr) { $DufsAddr = "http://localhost:5555" }

$ContainerName = "dapr-bindings-test"
$DaprPort = 3600
$Mirror = "n5nsx2pw56rzh4.xuanyuan.run"

function Info($msg) { Write-Host "[INFO] $msg" -ForegroundColor Green }

# 1. Build WASM
Info "=== Build WASM ==="
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
Info "Built bindings.wasm ($('{0:N0}' -f (Get-Item "$ScriptDir\bindings.wasm").Length) bytes)"

# 2. Upload to dufs so Docker container can fetch it
Info "=== Upload to dufs ==="
$wslPath = $ScriptDir -replace '\\','/'
$wslPath = $wslPath -replace '^([A-Za-z]):','/mnt/$1'
$wslPath = $wslPath.ToLower().Substring(0,6) + $wslPath.Substring(6)
wsl curl -s -T "$wslPath/bindings.wasm" $DufsAddr/bindings.wasm
Info "Uploaded bindings.wasm to dufs"

# 3. Stop previous container
Info "=== Cleanup previous ==="
docker stop $ContainerName 2>$null | Out-Null
docker rm $ContainerName 2>$null | Out-Null

# 4. Prepare component yaml (write to temp dir, mount into container)
$tmpDir = "$ScriptDir\test-docker-components"
if (Test-Path $tmpDir) { Remove-Item -Recurse -Force $tmpDir }
New-Item -ItemType Directory -Path $tmpDir | Out-Null

# Use host.docker.internal to reach dufs from inside Docker container
@"
apiVersion: dapr.io/v1alpha1
kind: Component
metadata:
  name: wasm
spec:
  type: bindings.wasm
  version: v1
  metadata:
    - name: url
      value: "http://host.docker.internal:5555/bindings.wasm"
"@ | Set-Content -Path "$tmpDir\wasm-binding.yaml" -Encoding UTF8

@"
apiVersion: dapr.io/v1alpha1
kind: Configuration
metadata:
  name: daprConfig
spec:
  metric:
    enabled: false
  logging:
    apiLogging:
      enabled: true
"@ | Set-Content -Path "$tmpDir\config.yaml" -Encoding UTF8

Info "Component yaml:"
Get-Content "$tmpDir\wasm-binding.yaml"

# 5. Run daprd in Docker (Linux image has wasm support)
Info "=== Starting daprd in Docker ==="
$image = "$Mirror/daprio/daprd:1.16.9"
Info "Image: $image"

# Convert Windows path to Docker-compatible mount path
$mountPath = $tmpDir -replace '\\','/'
$mountPath = $mountPath -replace '^([A-Za-z]):','/$1'

docker run -d `
    --name $ContainerName `
    --network host `
    -v "${mountPath}:/components" `
    $image `
    ./daprd `
    -app-id dapr-bindings-test `
    -dapr-http-port $DaprPort `
    -resources-path /components `
    -config /components/config.yaml `
    -placement-host-address 172.26.64.1:50000 `
    -log-level info

if ($LASTEXITCODE -ne 0) {
    Write-Host "Docker run failed!" -ForegroundColor Red
    exit 1
}

Info "Container started, waiting 8s for daprd to initialize..."
Start-Sleep -Seconds 8

# 6. Check logs
Info "=== daprd logs ==="
docker logs $ContainerName 2>&1 | Select-Object -Last 30

# 7. Test invoke
Write-Host ""
Info "=== Test bindings invoke ==="
Info "Testing health..."
$result = wsl curl -s -X POST "http://localhost:$DaprPort/v1.0/bindings/wasm" `
    -H "Content-Type: application/json" `
    -d '{\"operation\":\"execute\",\"data\":\"{\\\"action\\\":\\\"health\\\"}\"}'
Write-Host "Response: $result"

Write-Host ""
Info "Testing echo..."
$result2 = wsl curl -s -X POST "http://localhost:$DaprPort/v1.0/bindings/wasm" `
    -H "Content-Type: application/json" `
    -d '{\"operation\":\"execute\",\"data\":\"{\\\"action\\\":\\\"echo\\\",\\\"data\\\":\\\"hello wasm\\\"}\"}'
Write-Host "Response: $result2"

Write-Host ""
Info "Testing upper..."
$result3 = wsl curl -s -X POST "http://localhost:$DaprPort/v1.0/bindings/wasm" `
    -H "Content-Type: application/json" `
    -d '{\"operation\":\"execute\",\"data\":\"{\\\"action\\\":\\\"upper\\\",\\\"data\\\":\\\"hello world\\\"}\"}'
Write-Host "Response: $result3"

# 8. Cleanup instructions
Write-Host ""
Info "=== Done ==="
Info "Container '$ContainerName' is running on port $DaprPort"
Info "To stop: docker stop $ContainerName; docker rm $ContainerName"
Info "To view logs: docker logs -f $ContainerName"
