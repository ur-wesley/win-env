. (Join-Path $PSScriptRoot 'strip-apps.ps1')

if (-not (Get-Command lwm -ErrorAction SilentlyContinue)) { exit 1 }

$null = lwm reload 2>&1
Start-Sleep -Milliseconds 250

foreach ($w in Get-ManagedWindows) {
    if (Test-RetileExe $w.exe -or Test-LayoutRepairExe $w.exe) {
        Repair-TiledWindow $w.hwnd $w.exe $w.title
    }
}

$null = lwm refresh 2>&1
Start-Sleep -Milliseconds 200
$null = lwm center-column 2>&1
