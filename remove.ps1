param([switch]$StopLeopardwm)

$RepoRoot = Join-Path $env:APPDATA 'leopardwm'
$BarDir = Join-Path $RepoRoot 'bar'
$YasbLive = Join-Path $env:USERPROFILE '.config\yasb'
$YasbRepo = Join-Path $RepoRoot 'yasb'
$YasbBak = "$YasbLive.bak"

function Stop-BarPid([string]$PidFile) {
    if (-not (Test-Path $PidFile)) { return }
    $id = Get-Content $PidFile -ErrorAction SilentlyContinue
    if ($id) { Stop-Process -Id $id -Force -ErrorAction SilentlyContinue }
    Remove-Item $PidFile -Force -ErrorAction SilentlyContinue
}

function Remove-RunKey([string]$Name) {
    Remove-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name $Name -ErrorAction SilentlyContinue
}

Get-Process yasb -ErrorAction SilentlyContinue | Stop-Process -Force

Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like "*leopardwm\bar*" } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

foreach ($name in @('bridge.pid', 'hotkeys.pid', 'restore.pid')) {
    Stop-BarPid (Join-Path $BarDir $name)
}

Remove-RunKey 'LeopardWM-Bar'

if (Get-Command lwm -ErrorAction SilentlyContinue) {
    lwm autostart disable 2>$null
}

if (Test-Path $YasbLive) {
    $item = Get-Item $YasbLive -Force
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        $target = $item.Target
        if ($target -and ($target -eq $YasbRepo -or $target[0] -eq $YasbRepo)) {
            Remove-Item $YasbLive -Force
        }
    }
}

if ((Test-Path $YasbBak) -and -not (Test-Path $YasbLive)) {
    Rename-Item $YasbBak (Split-Path $YasbLive -Leaf)
}

$prevEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
try { & (Join-Path $BarDir 'show-taskbar.ps1') } catch { }
$ErrorActionPreference = $prevEap

if ($StopLeopardwm) {
    Get-Process leopardwm,leopardwm-watchdog -ErrorAction SilentlyContinue | Stop-Process -Force
}

Write-Host "win-env removed (bar + autostart unwired, taskbar restored)"
if (-not $StopLeopardwm) {
    Write-Host "LeopardWM still running — pass -StopLeopardwm to stop it"
}
