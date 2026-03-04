. "$PSScriptRoot\..\..\.env.ps1"

$jobFile = "$PSScriptRoot\traefik.nomad.hcl"
$jobHCL = (Get-Content $jobFile -Raw) -replace '\\', '\\\\' -replace '"', '\"' -replace "`r`n", '\n' -replace "`n", '\n'
$body = "{`"JobHCL`":`"$jobHCL`",`"Canonicalize`":false}"

Write-Host "[INFO] Deploying traefik..."
$resp = Invoke-RestMethod -Uri "http://localhost:4646/v1/jobs/parse" -Method POST -Body $body -ContentType "application/json"
$jobJson = $resp | ConvertTo-Json -Depth 100
$submitBody = "{`"Job`":$jobJson}"
Invoke-RestMethod -Uri "http://localhost:4646/v1/jobs" -Method POST -Body $submitBody -ContentType "application/json"
Write-Host "[INFO] Traefik deployed."
