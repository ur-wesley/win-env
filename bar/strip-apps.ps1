$script:StripApps = @{
    'zen.exe'        = 1
    'helium.exe'     = 1
    'vivaldi.exe'    = 1
    'fastpotify.exe' = 3
    'discord.exe'    = 3
}

$script:RetileExes = @{}

$script:LayoutRepairExes = @{
    'zed.exe'         = $true
    'okena.exe'       = $true
    'cursor.exe'      = $true
    'antigravity.exe' = $true
    'discord.exe'     = $true
}

$script:OverflowEpsilon = 4
$script:LwmExe = Join-Path ${env:ProgramFiles} 'LeopardWM\bin\lwm.exe'
if (-not (Test-Path $script:LwmExe)) { $script:LwmExe = 'lwm' }

function Invoke-Lwm {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)
    & $script:LwmExe @Args
}

if (-not ([System.Management.Automation.PSTypeName]'LwmTileHeal').Type) {
    Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class LwmTileHeal {
    public const int DWMWA_EXTENDED_FRAME_BOUNDS = 9;
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll")] public static extern int GetSystemMetrics(int nIndex);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassNameW(IntPtr hWnd, StringBuilder lpClassName, int nMaxCount);
    [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);
    [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr hwnd, int dwAttribute, out RECT pvAttribute, int cbAttribute);
}
"@
}

function Test-LayoutRepairExe([string]$executable) {
    $name = [System.IO.Path]::GetFileName($executable)
    if (-not $name) { return $false }
    return $script:LayoutRepairExes.ContainsKey($name.ToLowerInvariant())
}

function Test-RetileExe([string]$executable) {
    $name = [System.IO.Path]::GetFileName($executable)
    if (-not $name) { return $false }
    return $script:RetileExes.ContainsKey($name.ToLowerInvariant())
}

function Get-WindowClassName([int64]$hwnd) {
    if ($hwnd -le 0) { return '' }
    if (-not [LwmTileHeal]::IsWindow([IntPtr]$hwnd)) { return '' }
    $sb = New-Object System.Text.StringBuilder 256
    $len = [LwmTileHeal]::GetClassNameW([IntPtr]$hwnd, $sb, $sb.Capacity)
    if ($len -le 0) { return '' }
    return $sb.ToString()
}

function Get-TileViewport {
    $gapL = 0
    $gapR = 0
    $gapT = 36
    $gapB = 0
    $cfgPath = Join-Path $env:APPDATA 'leopardwm\config\config.toml'
    if (Test-Path $cfgPath) {
        $cfg = Get-Content $cfgPath -Raw
        if ($cfg -match '(?m)^\s*outer_gap_left\s*=\s*(\d+)') { $gapL = [int]$Matches[1] }
        if ($cfg -match '(?m)^\s*outer_gap_right\s*=\s*(\d+)') { $gapR = [int]$Matches[1] }
        if ($cfg -match '(?m)^\s*outer_gap_top\s*=\s*(\d+)') { $gapT = [int]$Matches[1] }
        if ($cfg -match '(?m)^\s*outer_gap_bottom\s*=\s*(\d+)') { $gapB = [int]$Matches[1] }
    }
    $screenW = [LwmTileHeal]::GetSystemMetrics(0)
    $screenH = [LwmTileHeal]::GetSystemMetrics(1)
    return @{
        Left   = $gapL
        Top    = $gapT
        Right  = $screenW - $gapR
        Bottom = $screenH - $gapB
    }
}

function Get-WindowVisibleRect([int64]$hwnd) {
    if ($hwnd -le 0) { return $null }
    if (-not [LwmTileHeal]::IsWindow([IntPtr]$hwnd)) { return $null }
    $rect = New-Object LwmTileHeal+RECT
    $hr = [LwmTileHeal]::DwmGetWindowAttribute([IntPtr]$hwnd, [LwmTileHeal]::DWMWA_EXTENDED_FRAME_BOUNDS, [ref]$rect, 16)
    if ($hr -ne 0) { return $null }
    return @{
        Left   = $rect.Left
        Top    = $rect.Top
        Right  = $rect.Right
        Bottom = $rect.Bottom
    }
}

function Test-VisibleOverflow($visible, $viewport, [int]$epsilon = $script:OverflowEpsilon) {
    if ($visible.Top -lt ($viewport.Top - $epsilon)) { return $true }
    if ($visible.Left -lt ($viewport.Left - $epsilon)) { return $true }
    if ($visible.Right -gt ($viewport.Right + $epsilon)) { return $true }
    if ($visible.Bottom -gt ($viewport.Bottom + $epsilon)) { return $true }
    return $false
}

function Test-VisibleUnderflow($visible, $viewport, [int]$epsilon = $script:OverflowEpsilon) {
    if ($visible.Top -gt ($viewport.Top + $epsilon)) { return $false }
    $visH = $visible.Bottom - $visible.Top
    $wantH = $viewport.Bottom - $viewport.Top
    if ($visH -lt ($wantH - $epsilon)) { return $true }
    return $false
}

function Test-ChromiumTarget([int64]$hwnd, [string]$executable) {
    if (Get-WindowClassName $hwnd -eq 'Chrome_WidgetWin_1') { return $true }
    if (Test-LayoutRepairExe $executable) { return $true }
    return $false
}

function Test-WindowOverflowsViewport([int64]$hwnd) {
    $visible = Get-WindowVisibleRect $hwnd
    if (-not $visible) { return $false }
    return Test-VisibleOverflow $visible (Get-TileViewport)
}

function Test-WindowUnderflowsViewport([int64]$hwnd) {
    $visible = Get-WindowVisibleRect $hwnd
    if (-not $visible) { return $false }
    return Test-VisibleUnderflow $visible (Get-TileViewport)
}

function Test-WindowNeedsGeometryHeal([int64]$hwnd) {
    return (Test-WindowOverflowsViewport $hwnd) -or (Test-WindowUnderflowsViewport $hwnd)
}

function Invoke-NudgeWindowGeometry([int64]$hwnd) {
    if ($hwnd -le 0) { return }
    if (-not [LwmTileHeal]::IsWindow([IntPtr]$hwnd)) { return }
    $r = New-Object LwmTileHeal+RECT
    if (-not [LwmTileHeal]::GetWindowRect([IntPtr]$hwnd, [ref]$r)) { return }
    $x = $r.Left
    $y = $r.Top
    $w = $r.Right - $r.Left
    $h = $r.Bottom - $r.Top
    if ($w -lt 2 -or $h -lt 2) { return }
    $flags = [uint32]0x0014
    [void][LwmTileHeal]::SetWindowPos([IntPtr]$hwnd, [IntPtr]::Zero, $x, $y, $w, $h - 1, $flags)
    [void][LwmTileHeal]::SetWindowPos([IntPtr]$hwnd, [IntPtr]::Zero, $x, $y, $w, $h, $flags)
    [void][LwmTileHeal]::SetWindowPos([IntPtr]$hwnd, [IntPtr]::Zero, $x, $y, $w - 1, $h, $flags)
    [void][LwmTileHeal]::SetWindowPos([IntPtr]$hwnd, [IntPtr]::Zero, $x, $y, $w, $h, $flags)
}

function Invoke-HealTiledWindow([int64]$hwnd, [switch]$Force) {
    if ($hwnd -le 0) { return $false }
    if (-not $Force -and -not (Test-WindowNeedsGeometryHeal $hwnd)) { return $false }

    $null = Invoke-Lwm refresh 2>&1
    Start-Sleep -Milliseconds 150
    if (-not (Test-WindowNeedsGeometryHeal $hwnd)) { return $true }

    [void][LwmTileHeal]::ShowWindow([IntPtr]$hwnd, 6)
    Start-Sleep -Milliseconds 80
    [void][LwmTileHeal]::ShowWindow([IntPtr]$hwnd, 9)
    Start-Sleep -Milliseconds 80
    $null = Invoke-Lwm refresh 2>&1
    Start-Sleep -Milliseconds 150
    if (-not (Test-WindowNeedsGeometryHeal $hwnd)) { return $true }

    Invoke-NudgeWindowGeometry $hwnd
    Start-Sleep -Milliseconds 80
    $null = Invoke-Lwm refresh 2>&1
    Start-Sleep -Milliseconds 150
    if (-not (Test-WindowNeedsGeometryHeal $hwnd)) { return $true }

    & (Join-Path $PSScriptRoot 'lwm-focus-window.ps1') -Hwnd ([int]$hwnd)
    Start-Sleep -Milliseconds 80
    $null = Invoke-Lwm toggle-floating 2>&1
    Start-Sleep -Milliseconds 80
    $null = Invoke-Lwm toggle-floating 2>&1
    Start-Sleep -Milliseconds 150
    $null = Invoke-Lwm refresh 2>&1
    return $true
}

function Repair-TiledWindow([int64]$hwnd, [string]$executable = '', [string]$title = '', [switch]$Force) {
    if ($executable -match 'zed' -and -not $title) { return }
    if (-not $Force -and -not (Test-ChromiumTarget $hwnd $executable)) { return }
    Invoke-HealTiledWindow $hwnd -Force:$Force
}

function Repair-OverflowingWindows {
    if (-not (Test-Path $script:LwmExe) -and -not (Get-Command lwm -ErrorAction SilentlyContinue)) { return 0 }
    $healed = 0
    foreach ($w in Get-ManagedWindows) {
        if ($w.exe -match 'zed' -and -not $w.title) { continue }
        if (-not (Test-ChromiumTarget $w.hwnd $w.exe)) { continue }
        if (-not (Test-WindowNeedsGeometryHeal $w.hwnd)) { continue }
        if (Invoke-HealTiledWindow $w.hwnd) { $healed++ }
    }
    return $healed
}

function Get-StripForExe([string]$executable, [string]$title = '') {
    $name = [System.IO.Path]::GetFileName($executable)
    if (-not $name) { return 2 }
    $key = $name.ToLowerInvariant()
    if ($script:StripApps.ContainsKey($key)) { return [int]$script:StripApps[$key] }
    if ($key -eq 'chrome.exe' -and $title -match 'Helium') { return 1 }
    return 2
}

function Test-StripClassified([string]$executable, [string]$title = '') {
    return (Get-StripForExe $executable $title) -ne 2
}

function Get-ManagedWindows {
    $all = (Invoke-Lwm query all 2>&1) | Out-String
    foreach ($line in ($all -split "`n")) {
        if ($line -notmatch '^\s*(\d+)\s+-\s+(.+?)\s+\(([^)]+)\)') { continue }
        [pscustomobject]@{ hwnd = [int64]$Matches[1]; title = $Matches[2].Trim(); exe = $Matches[3].Trim() }
    }
}

function Move-HwndToStrip([int64]$hwnd, [int]$strip, [string]$exe = '') {
    & (Join-Path $PSScriptRoot 'lwm-focus-window.ps1') -Hwnd ([int]$hwnd)
    $null = Invoke-Lwm move-to-workspace $strip 2>&1
}

function Place-ManagedWindows {
    $ws = (Invoke-Lwm query workspace 2>&1) | Out-String
    $prev = 2
    if ($ws -match 'Active workspace:\s*(\d+)') { $prev = [int]$Matches[1] }
    if ($prev -lt 1 -or $prev -gt 3) { $prev = 2 }
    foreach ($w in Get-ManagedWindows) {
        Move-HwndToStrip $w.hwnd (Get-StripForExe $w.exe $w.title) $w.exe
    }
    $null = Invoke-Lwm workspace $prev 2>&1
}

if ($MyInvocation.InvocationName -ne '.' -and $MyInvocation.Line -notmatch '^\s*\.') {
    $script:fail = 0
    function Assert-Strip([string]$exe, [int]$want, [string]$title = '') {
        $got = Get-StripForExe $exe $title
        if ($got -ne $want) {
            Write-Error "Get-StripForExe $exe '$title' -> $got want $want"
            $script:fail++
        }
    }
    function Assert-Overflow([hashtable]$visible, [hashtable]$viewport, [bool]$want, [string]$label) {
        $got = Test-VisibleOverflow $visible $viewport
        if ($got -ne $want) {
            Write-Error "Test-VisibleOverflow $label -> $got want $want"
            $script:fail++
        }
    }
    Assert-Strip 'zen.exe' 1
    Assert-Strip 'C:\x\HELIUM.EXE' 1
    Assert-Strip 'Vivaldi.exe' 1
    Assert-Strip 'chrome.exe' 1 'Neuer Tab - Helium'
    Assert-Strip 'chrome.exe' 2 'Gmail'
    Assert-Strip 'fastpotify.exe' 3
    Assert-Strip 'Discord.exe' 3
    Assert-Strip 'Cursor.exe' 2
    Assert-Strip 'Zed.exe' 2
    Assert-Strip '' 2
    if (-not (Test-StripClassified 'helium.exe')) { Write-Error 'helium should be classified'; $script:fail++ }
    if (Test-StripClassified 'notepad.exe') { Write-Error 'notepad should not be classified'; $script:fail++ }
    if (-not (Test-LayoutRepairExe 'Discord.exe')) { Write-Error 'discord should be repair exe'; $script:fail++ }
    $vp = @{ Left = 0; Top = 36; Right = 2560; Bottom = 1440 }
    Assert-Overflow @{ Left = 0; Top = 36; Right = 2560; Bottom = 1440 } $vp $false 'inside'
    Assert-Overflow @{ Left = 0; Top = 31; Right = 2560; Bottom = 1440 } $vp $true 'above bar'
    Assert-Overflow @{ Left = -5; Top = 36; Right = 2560; Bottom = 1440 } $vp $true 'past left'
    Assert-Overflow @{ Left = 0; Top = 36; Right = 2565; Bottom = 1440 } $vp $true 'past right'
    Assert-Overflow @{ Left = 0; Top = 36; Right = 2560; Bottom = 1445 } $vp $true 'past bottom'
    Assert-Overflow @{ Left = 0; Top = 33; Right = 2560; Bottom = 1440 } $vp $false 'within epsilon'
    function Assert-Underflow([hashtable]$visible, [hashtable]$viewport, [bool]$want, [string]$label) {
        $got = Test-VisibleUnderflow $visible $viewport
        if ($got -ne $want) {
            Write-Error "Test-VisibleUnderflow $label -> $got want $want"
            $script:fail++
        }
    }
    Assert-Underflow @{ Left = 0; Top = 36; Right = 2560; Bottom = 1400 } $vp $true 'short height'
    Assert-Underflow @{ Left = 0; Top = 36; Right = 2560; Bottom = 1440 } $vp $false 'full height'
    if ($script:fail -ne 0) { exit 1 }
    Write-Output 'strip-apps ok'
}
