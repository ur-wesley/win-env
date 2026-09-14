param([int]$Hwnd = 0)

. (Join-Path $PSScriptRoot 'strip-apps.ps1')

$LogFile = Join-Path $PSScriptRoot 'retile.log'

function Write-RetileLog([string]$msg) {
    try { Add-Content -Path $LogFile -Value ((Get-Date).ToString('HH:mm:ss') + ' ' + $msg) } catch { }
}

if (-not ([System.Management.Automation.PSTypeName]'LwmRetileFg').Type) {
    Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class LwmRetileFg {
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint procId);
}
"@
}

function Get-LwmFocusedHwndFromAll {
    $all = (Invoke-Lwm query all 2>&1) | Out-String
    foreach ($line in ($all -split "`n")) {
        if ($line -match '^\s*(\d+)\s+-.+\[FOCUSED\]') { return [int64]$Matches[1] }
    }
    return 0
}

function Get-LwmFocusedHwnd {
    $focused = (Invoke-Lwm query focused 2>&1) | Out-String
    if ($focused -match 'Window ID:\s*(\d+)') { return [int64]$Matches[1] }
    return 0
}

function Get-ForegroundHwnd {
    return [int64][LwmRetileFg]::GetForegroundWindow()
}

function Get-ExeForHwnd([int64]$hwnd) {
    [uint32]$procId = 0
    [void][LwmRetileFg]::GetWindowThreadProcessId([IntPtr]$hwnd, [ref]$procId)
    if (-not $procId) { return '' }
    $proc = Get-Process -Id $procId -ErrorAction SilentlyContinue
    if (-not $proc) { return '' }
    return $proc.Path
}

function Find-Managed([int64]$hwnd) {
    foreach ($w in Get-ManagedWindows) {
        if ($w.hwnd -eq $hwnd) { return $w }
    }
    return $null
}

try { [console]::beep(880, 60) } catch { }

if (-not $Hwnd) { $Hwnd = Get-LwmFocusedHwndFromAll }
if (-not $Hwnd) { $Hwnd = Get-LwmFocusedHwnd }
if (-not $Hwnd) { $Hwnd = Get-ForegroundHwnd }
if (-not $Hwnd) {
    Write-RetileLog 'no hwnd'
    exit 1
}

Write-RetileLog "heal hwnd=$Hwnd"

$managed = Find-Managed $Hwnd
if ($managed) {
    if ($managed.exe -match 'zed' -and -not $managed.title) {
        Write-RetileLog 'skip zed splash'
        exit 0
    }
    Invoke-HealTiledWindow $Hwnd -Force | Out-Null
    Write-RetileLog 'done managed'
    exit 0
}

$exe = Get-ExeForHwnd $Hwnd
if ($exe -match 'zed') {
    Write-RetileLog 'skip unmanaged zed'
    exit 0
}

Invoke-HealTiledWindow $Hwnd -Force | Out-Null
Write-RetileLog 'done foreground'
