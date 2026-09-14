. (Join-Path $PSScriptRoot 'strip-apps.ps1')

if (-not (Get-Command lwm -ErrorAction SilentlyContinue)) { exit 1 }

$null = Invoke-Lwm reload 2>&1
Start-Sleep -Milliseconds 250

Repair-OverflowingWindows | Out-Null

$null = Invoke-Lwm refresh 2>&1
