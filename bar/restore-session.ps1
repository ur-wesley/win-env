$mutex = New-Object System.Threading.Mutex($false, 'Global\LeopardWM-Session-Restore')
$mutexAcquired = $false
try {
if (-not $mutex.WaitOne(0)) { exit 0 }
$mutexAcquired = $true

$BarDir = Join-Path $env:APPDATA "leopardwm\bar"
$LogFile = Join-Path $BarDir "restore-session.log"
$SessionFile = Join-Path $env:APPDATA "leopardwm\data\session-layout.json"

function Write-RestoreLog([string]$msg) {
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $msg"
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
}

function Wait-ForLwm([int]$seconds = 60) {
    $deadline = (Get-Date).AddSeconds($seconds)
    while ((Get-Date) -lt $deadline) {
        if (Get-Command lwm -ErrorAction SilentlyContinue) {
            $out = (lwm query workspace 2>&1) | Out-String
            if ($out -match 'Active workspace:') { return $true }
        }
        Start-Sleep -Milliseconds 500
    }
    return $false
}

function Get-LiveWindows {
    $items = @()
    $all = (lwm query all 2>&1) | Out-String
    foreach ($line in ($all -split "`n")) {
        if ($line -notmatch '^\s*(\d+)\s+-\s+(.+?)\s+\(([^)]*)\)') { continue }
        $hwnd = [int64]$Matches[1]
        $title = $Matches[2].Trim()
        $exe = $Matches[3].Trim()
        $col = 0
        if ($line -match '\[col (\d+)') { $col = [int]$Matches[1] }
        $items += [pscustomobject]@{ hwnd = $hwnd; title = $title; exe = $exe; col = $col }
    }
    return $items
}

function Test-TitleMatch([string]$saved, [string]$live) {
    if (-not $saved -or -not $live) { return $true }
    if ($saved -eq $live) { return $true }
    if ($live.Contains($saved) -or $saved.Contains($live)) { return $true }
    return $false
}

function Find-LiveWindow($saved, $liveWindows, $used) {
    $exe = $saved.exe
    if (-not $exe) { return $null }
    $candidates = @($liveWindows | Where-Object {
        $_.exe -and $_.exe.ToLowerInvariant() -eq $exe.ToLowerInvariant() -and -not $used.Contains($_.hwnd)
    })
    if ($candidates.Count -eq 0) { return $null }
    if ($candidates.Count -eq 1) { return $candidates[0] }
    $titleMatch = @($candidates | Where-Object { Test-TitleMatch $saved.title $_.title })
    if ($titleMatch.Count -eq 1) { return $titleMatch[0] }
    return $candidates[0]
}

function Test-ExePresent([string]$exe, $liveWindows) {
    if (-not $exe) { return $false }
    return @($liveWindows | Where-Object { $_.exe -and $_.exe.ToLowerInvariant() -eq $exe.ToLowerInvariant() }).Count -gt 0
}

function Launch-SavedWindow($saved, [int]$timeoutSec = 45) {
    $liveWindows = Get-LiveWindows
    if (Test-ExePresent $saved.exe $liveWindows) {
        Write-RestoreLog "skip launch $($saved.exe): already open"
        return $true
    }
    if (-not $saved.launch -or -not (Test-Path $saved.launch)) {
        Write-RestoreLog "skip launch $($saved.exe): no path"
        return $false
    }
    Write-RestoreLog "launch $($saved.exe) -> $($saved.launch)"
    try {
        Start-Process -FilePath $saved.launch | Out-Null
    } catch {
        Write-RestoreLog "launch failed $($saved.exe): $_"
        return $false
    }
    $deadline = (Get-Date).AddSeconds($timeoutSec)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 500
        $liveWindows = Get-LiveWindows
        if (Test-ExePresent $saved.exe $liveWindows) { return $true }
    }
    Write-RestoreLog "timeout waiting for $($saved.exe)"
    return $false
}

function Focus-Window([int64]$hwnd) {
    & (Join-Path $BarDir 'lwm-focus-window.ps1') -Hwnd ([int]$hwnd)
}

function Get-FocusedColumnInWorkspace {
    $ws = (lwm query workspace 2>&1) | Out-String
    if ($ws -match 'Focused column:\s*(\d+)') { return [int]$Matches[1] }
    return -1
}

function Move-WindowToColumn([int64]$hwnd, [int]$targetCol) {
    Focus-Window $hwnd
    Start-Sleep -Milliseconds 80
    $guard = 0
    while ($guard++ -lt 16) {
        $col = Get-FocusedColumnInWorkspace
        if ($col -lt 0) { return }
        if ($col -eq $targetCol) { return }
        if ($col -lt $targetCol) {
            $null = lwm move right 2>&1
        } else {
            $null = lwm move left 2>&1
        }
        Start-Sleep -Milliseconds 120
    }
}

function Move-WindowToStrip([int64]$hwnd, [int]$strip) {
    Focus-Window $hwnd
    $null = lwm move-to-workspace $strip 2>&1
    Start-Sleep -Milliseconds 80
}

Write-RestoreLog 'restore start'

if (-not (Wait-ForLwm)) {
    Write-RestoreLog 'lwm not ready, exit'
    exit 1
}

if (-not (Test-Path $SessionFile)) {
    Write-RestoreLog 'no session-layout.json, exit'
    exit 0
}

try {
    $session = Get-Content $SessionFile -Raw | ConvertFrom-Json
} catch {
    Write-RestoreLog "bad session file: $_"
    exit 1
}

if (-not $session.workspaces -or @($session.workspaces).Count -eq 0) {
    Write-RestoreLog 'empty session, exit'
    exit 0
}

$liveWindows = Get-LiveWindows
$launched = @{}

foreach ($ws in @($session.workspaces)) {
    foreach ($col in @($ws.columns)) {
        foreach ($saved in @($col.windows)) {
            if (-not $saved.exe -or -not $saved.launch) { continue }
            $key = $saved.exe.ToLowerInvariant()
            if ($launched.ContainsKey($key)) { continue }
            $launched[$key] = $true
            $null = Launch-SavedWindow $saved
        }
    }
}

Start-Sleep -Seconds 2
$liveWindows = Get-LiveWindows
Write-RestoreLog "strip pass ($($liveWindows.Count) live windows)"
$used = [System.Collections.Generic.HashSet[int64]]::new()
$resolved = [System.Collections.Generic.List[object]]::new()

foreach ($ws in @($session.workspaces)) {
    $strip = [int]$ws.index
    $colIdx = 0
    foreach ($col in @($ws.columns)) {
        foreach ($saved in @($col.windows)) {
            $live = Find-LiveWindow $saved $liveWindows $used
            if (-not $live) {
                Write-RestoreLog "missing $($saved.exe) '$($saved.title)' on strip $strip"
                continue
            }
            $used.Add($live.hwnd) | Out-Null
            Move-WindowToStrip $live.hwnd $strip
            $resolved.Add([pscustomobject]@{
                hwnd       = $live.hwnd
                exe        = $live.exe
                strip      = $strip
                target_col = $colIdx
            })
        }
        $colIdx++
    }
}

Write-RestoreLog "column pass ($($resolved.Count) windows)"
foreach ($ws in @($session.workspaces)) {
    $strip = [int]$ws.index
    $null = lwm workspace $strip 2>&1
    Start-Sleep -Milliseconds 150
    $targets = @($resolved | Where-Object { $_.strip -eq $strip } | Sort-Object target_col)
    foreach ($t in $targets) {
        Move-WindowToColumn $t.hwnd ([int]$t.target_col)
    }
}

$null = lwm refresh 2>&1

if ($session.active_workspace) {
    $active = [int]$session.active_workspace
    if ($active -ge 1 -and $active -le 3) {
        $null = lwm workspace $active 2>&1
    }
}

Write-RestoreLog "restore done ($($resolved.Count) windows)"
} finally {
    if ($mutexAcquired) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}
exit 0
