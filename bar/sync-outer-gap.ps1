$Root = Join-Path $env:APPDATA "leopardwm"
$ConfigPath = Join-Path $Root "config\config.toml"

if (-not (Test-Path $ConfigPath) -or -not (Get-Command lwm -ErrorAction SilentlyContinue)) { exit 0 }

function Get-ConfigInt([string]$name) {
    $cfg = Get-Content $ConfigPath -Raw
    if ($cfg -match "(?m)^\s*$([regex]::Escape($name))\s*=\s*(\d+)") { return [int]$Matches[1] }
    return $null
}

$want = Get-ConfigInt 'outer_gap_top'
if ($null -eq $want) { exit 0 }

$null = lwm reload 2>&1
Start-Sleep -Milliseconds 200
$null = lwm refresh 2>&1
