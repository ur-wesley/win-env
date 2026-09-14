param([switch]$PatchCalendar)

$ErrorActionPreference = 'Stop'
$TargetRoot = Join-Path $env:APPDATA 'leopardwm'
$SourceRoot = $PSScriptRoot

function Ensure-WingetPackage([string]$Id) {
    $q = winget list --id $Id -e 2>&1 | Out-String
    if ($q -notmatch [regex]::Escape($Id)) {
        winget install --id $Id -e --accept-package-agreements --accept-source-agreements
    }
}

function Sync-RepoToTarget {
    if ((Resolve-Path $SourceRoot).Path -eq (Resolve-Path $TargetRoot).Path) { return }
    $exclude = @('.git', 'data', 'bar\status.json')
    foreach ($item in Get-ChildItem $SourceRoot -Force) {
        if ($item.Name -in $exclude) { continue }
        $dest = Join-Path $TargetRoot $item.Name
        if ($item.PSIsContainer) {
            if (-not (Test-Path $dest)) { New-Item -ItemType Directory -Path $dest -Force | Out-Null }
            Copy-Item $item.FullName $dest -Recurse -Force
        } else {
            Copy-Item $item.FullName $dest -Force
        }
    }
}

function Rewrite-YasbPaths([string]$ConfigPath) {
    $escaped = $env:APPDATA.Replace('\', '\\')
    $text = Get-Content $ConfigPath -Raw
    $text = $text -replace '\{\{APPDATA\}\}', $escaped
    $text = $text -replace 'C:\\Users\\[^\\]+\\AppData\\Roaming', $escaped
    Set-Content -Path $ConfigPath -Value $text -NoNewline
}

function Ensure-YasbJunction([string]$RepoRoot) {
    $yasbLive = Join-Path $env:USERPROFILE '.config\yasb'
    $yasbRepo = Join-Path $RepoRoot 'yasb'
    $configDir = Split-Path $yasbLive -Parent
    if (-not (Test-Path $configDir)) { New-Item -ItemType Directory -Path $configDir -Force | Out-Null }
    if (-not (Test-Path $yasbRepo)) { throw "Missing $yasbRepo" }

    if (Test-Path $yasbLive) {
        $item = Get-Item $yasbLive -Force
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            $target = (Get-Item $yasbLive).Target
            if ($target -and ($target -eq $yasbRepo -or $target[0] -eq $yasbRepo)) { return }
            Remove-Item $yasbLive -Force
        } else {
            $bak = "$yasbLive.bak"
            if (Test-Path $bak) { Remove-Item $bak -Recurse -Force }
            Rename-Item $yasbLive $bak
        }
    }
    cmd /c "mklink /J `"$yasbLive`" `"$yasbRepo`"" | Out-Null
}

function Set-RunKey([string]$Name, [string]$Command) {
    Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name $Name -Value $Command
}

function Remove-RunKey([string]$Name) {
    Remove-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name $Name -ErrorAction SilentlyContinue
}

function Ensure-Leopardwm {
    if (-not (Get-Command lwm -ErrorAction SilentlyContinue)) { return }
    $ok = $false
    try { $null = lwm query workspace 2>$null; $ok = $LASTEXITCODE -eq 0 } catch { }
    if ($ok) { return }
    $exe = "${env:ProgramFiles}\LeopardWM\bin\leopardwm.exe"
    if (-not (Test-Path $exe)) { return }
    Start-Process $exe
    foreach ($i in 1..10) {
        Start-Sleep -Milliseconds 500
        try { $null = lwm query workspace 2>$null; if ($LASTEXITCODE -eq 0) { return } } catch { }
    }
}

Ensure-WingetPackage 'jcardama.LeopardWM'
Ensure-WingetPackage 'AmN.yasb'
Sync-RepoToTarget
$RepoRoot = $TargetRoot

Get-Process yasb -ErrorAction SilentlyContinue | Stop-Process -Force
$yasbConfig = Join-Path $RepoRoot 'yasb\config.yaml'
Rewrite-YasbPaths $yasbConfig
Ensure-YasbJunction $RepoRoot

if (Get-Command lwm -ErrorAction SilentlyContinue) {
    lwm autostart enable 2>$null
}

$startBar = Join-Path $RepoRoot 'bar\start-bar.ps1'
Set-RunKey 'LeopardWM-Bar' "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$startBar`""
Remove-RunKey 'YASB'

Ensure-Leopardwm
$prevEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
try { & (Join-Path $RepoRoot 'bar\hide-taskbar.ps1') } catch { }
$ErrorActionPreference = $prevEap
Ensure-Leopardwm

if ($PatchCalendar) {
    & (Join-Path $RepoRoot 'bar\patch-yasb-calendar-weeks.ps1')
}

$barProc = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like "*start-bar.ps1*" }
if (-not $barProc) {
    Start-Process powershell.exe -ArgumentList "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$startBar`"" -WindowStyle Hidden
}

Write-Host "win-env ready at $RepoRoot"
Write-Host "Cheatsheet: $RepoRoot\config\CHEATSHEET.md"
