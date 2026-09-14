$script:StripApps = @{
    'zen.exe'        = 1
    'helium.exe'     = 1
    'vivaldi.exe'    = 1
    'fastpotify.exe' = 3
    'discord.exe'    = 3
}

$script:RetileExes = @{}

$script:LayoutRepairExes = @{
    'zed.exe' = $true
    'okena.exe' = $true
    'cursor.exe' = $true
    'antigravity.exe' = $true
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

function Repair-TiledWindow([int64]$hwnd, [string]$executable = '', [string]$title = '') {
    if ($executable -match 'zed' -and -not $title) { return }
    & (Join-Path $PSScriptRoot 'lwm-focus-window.ps1') -Hwnd ([int]$hwnd)
    Start-Sleep -Milliseconds 80
    if (Test-LayoutRepairExe $executable) {
        $null = lwm refresh 2>&1
        Start-Sleep -Milliseconds 120
        $null = lwm maximize-column 2>&1
    }
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
    $all = (lwm query all 2>&1) | Out-String
    foreach ($line in ($all -split "`n")) {
        if ($line -notmatch '^\s*(\d+)\s+-\s+(.+?)\s+\(([^)]+)\)') { continue }
        [pscustomobject]@{ hwnd = [int64]$Matches[1]; title = $Matches[2].Trim(); exe = $Matches[3].Trim() }
    }
}

function Move-HwndToStrip([int64]$hwnd, [int]$strip, [string]$exe = '') {
    & (Join-Path $PSScriptRoot 'lwm-focus-window.ps1') -Hwnd ([int]$hwnd)
    $null = lwm move-to-workspace $strip 2>&1
    if (Test-RetileExe $exe -or Test-LayoutRepairExe $exe) { Repair-TiledWindow $hwnd $exe }
}

function Place-ManagedWindows {
    $ws = (lwm query workspace 2>&1) | Out-String
    $prev = 2
    if ($ws -match 'Active workspace:\s*(\d+)') { $prev = [int]$Matches[1] }
    if ($prev -lt 1 -or $prev -gt 3) { $prev = 2 }
    foreach ($w in Get-ManagedWindows) {
        Move-HwndToStrip $w.hwnd (Get-StripForExe $w.exe $w.title) $w.exe
    }
    $null = lwm workspace $prev 2>&1
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
    if ($script:fail -ne 0) { exit 1 }
    Write-Output 'strip-apps ok'
}
