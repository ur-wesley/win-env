$mutex = New-Object System.Threading.Mutex($false, 'Global\LeopardWM-Bar-Start')
if (-not $mutex.WaitOne(0)) { exit 0 }

$BarDir = Join-Path $env:APPDATA "leopardwm\bar"
$Bridge = Join-Path $BarDir "lwm-status.ps1"
$Hotkeys = Join-Path $BarDir "lwm-hotkeys.ps1"
$Migrate = Join-Path $BarDir "migrate-workspaces.ps1"
$BridgePid = Join-Path $BarDir "bridge.pid"
$HotkeysPid = Join-Path $BarDir "hotkeys.pid"
$Restore = Join-Path $BarDir "restore-session.ps1"
$RestorePid = Join-Path $BarDir "restore.pid"

function Test-BarProcess([string]$PidFile) {
    if (-not (Test-Path $PidFile)) { return $false }
    $id = Get-Content $PidFile -ErrorAction SilentlyContinue
    if (-not $id) { return $false }
    $proc = Get-Process -Id $id -ErrorAction SilentlyContinue
    return $proc -and $proc.ProcessName -eq 'powershell'
}

function Start-HiddenSta([string]$File, [string]$PidFile) {
    if (Test-BarProcess $PidFile) { return }
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'powershell.exe'
    $psi.Arguments = "-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$File`""
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $proc = [System.Diagnostics.Process]::Start($psi)
    $proc.Id | Set-Content $PidFile
}

function Ensure-BarStack {
    if (Get-Command lwm -ErrorAction SilentlyContinue) {
        $ws = (lwm query workspace 2>&1) | Out-String
        if ($ws -match 'Active workspace:\s*(\d+)' -and [int]$Matches[1] -gt 3) {
            & $Migrate -Target 2
        }
    }
    Start-HiddenSta $Bridge $BridgePid
    Start-HiddenSta $Hotkeys $HotkeysPid
}

if (Get-Command lwm -ErrorAction SilentlyContinue) {
    & $Migrate -Target 2
}
Ensure-BarStack
Start-HiddenSta $Restore $RestorePid
& (Join-Path $BarDir "refresh-workarea.ps1")

if (-not (Get-Process yasb -ErrorAction SilentlyContinue)) {
    Start-Process "C:\Program Files\YASB\yasb.exe"
}

while ($true) {
    Start-Sleep -Seconds 15
    Ensure-BarStack
}
