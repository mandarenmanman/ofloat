# Check Consul service discovery (required by spin-app / dapr-bindings)
# Usage: .\check-consul-services.ps1 [-ConsulAddr "127.0.0.1:8500"]

param(
    [string]$ConsulAddr = "127.0.0.1:8500"
)

$base = "http://" + $ConsulAddr
Write-Host "=== Consul @ $ConsulAddr ===" -ForegroundColor Cyan

try {
    $leader = Invoke-RestMethod -Uri ($base + "/v1/status/leader") -ErrorAction Stop
    Write-Host "Leader: $leader" -ForegroundColor Green
} catch {
    Write-Host "Consul unreachable:" $_.Exception.Message -ForegroundColor Red
    Write-Host "Check: 1) Consul is running  2) consul.address in nomad client.hcl (e.g. 192.168.3.63:8500)" -ForegroundColor Yellow
    exit 1
}

$required = @("redis", "dapr-placement", "registry")
foreach ($name in $required) {
    try {
        $svc = Invoke-RestMethod -Uri ($base + "/v1/catalog/service/" + $name) -ErrorAction Stop
        if ($svc -and $svc.Count -gt 0) {
            $addr = $svc[0].ServiceAddress
            if (-not $addr) { $addr = $svc[0].Address }
            $port = $svc[0].ServicePort
            Write-Host "  $name : ${addr}:${port}" -ForegroundColor Green
        } else {
            Write-Host "  $name : (not registered)" -ForegroundColor Red
        }
    } catch {
        Write-Host "  $name : failed" $_.Exception.Message -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "If any service is missing, run in WSL: nomad job run nomad/redis.nomad.hcl" -ForegroundColor Yellow
Write-Host "  then: nomad job run nomad/dapr-placement.nomad.hcl and nomad job run nomad/registry.nomad.hcl" -ForegroundColor Yellow
