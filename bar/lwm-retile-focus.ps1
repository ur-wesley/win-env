param([int]$Hwnd = 0)

. (Join-Path $PSScriptRoot 'strip-apps.ps1')

if (-not ([System.Management.Automation.PSTypeName]'LwmRetileFg').Type) {
    Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class LwmRetileFg {
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint procId);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
"@
}

function Get-LwmFocusedHwnd {
    $focused = (lwm query focused 2>&1) | Out-String
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

function Remanage-Window([int64]$hwnd) {
    [void][LwmRetileFg]::ShowWindow([IntPtr]$hwnd, 6)
    Start-Sleep -Milliseconds 80
    [void][LwmRetileFg]::ShowWindow([IntPtr]$hwnd, 9)
    Start-Sleep -Milliseconds 80
    $null = lwm refresh 2>&1
    Start-Sleep -Milliseconds 150
}

function Repair-FocusedWindow([int64]$hwnd, [string]$exe, [string]$title = '') {
    if (-not $exe) { $exe = Get-ExeForHwnd $hwnd }
    Repair-TiledWindow $hwnd $exe $title
}

if (-not $Hwnd) { $Hwnd = Get-LwmFocusedHwnd }
if (-not $Hwnd) { $Hwnd = Get-ForegroundHwnd }

$managed = Find-Managed $Hwnd
if (-not $managed) {
    $null = lwm refresh 2>&1
    Start-Sleep -Milliseconds 150
    $managed = Find-Managed $Hwnd
}
if (-not $managed) {
    Remanage-Window $Hwnd
    $managed = Find-Managed $Hwnd
}

if ($managed) {
    if (Test-RetileExe $managed.exe) {
        Remanage-Window $Hwnd
    } elseif (Test-LayoutRepairExe $managed.exe) {
        $null = lwm refresh 2>&1
        Start-Sleep -Milliseconds 120
        $null = lwm maximize-column 2>&1
    } else {
        Repair-FocusedWindow $Hwnd $managed.exe $managed.title
    }
    exit 0
}

$exe = Get-ExeForHwnd $Hwnd
if ($exe -and (Test-LayoutRepairExe $exe -or Test-RetileExe $exe)) {
    Repair-FocusedWindow $Hwnd $exe
    exit 0
}

& (Join-Path $PSScriptRoot 'lwm-focus-window.ps1') -Hwnd ([int]$Hwnd)
Start-Sleep -Milliseconds 80
$null = lwm toggle-floating 2>&1
Start-Sleep -Milliseconds 80
$null = lwm toggle-floating 2>&1
