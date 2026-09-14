$script:SessionDataDir = Join-Path $env:APPDATA "leopardwm\data"
$script:SessionLayoutFile = Join-Path $script:SessionDataDir "session-layout.json"
$script:WorkspaceStateFile = Join-Path $script:SessionDataDir "workspace-state.json"
$script:SessionSaveDueAt = $null
$script:SessionLastHash = ''
$script:SessionLaunchCache = @{}

function Get-WindowMapFromQuery {
    $map = @{}
    $all = (lwm query all 2>&1) | Out-String
    foreach ($line in ($all -split "`n")) {
        if ($line -notmatch '^\s*(\d+)\s+-\s+(.+?)\s+\(([^)]*)\)') { continue }
        $hwnd = [int64]$Matches[1]
        $title = $Matches[2].Trim()
        $exe = $Matches[3].Trim()
        $map[$hwnd] = [ordered]@{ hwnd = $hwnd; title = $title; exe = $exe }
    }
    return $map
}

function Get-LaunchPathForWindow([int64]$hwnd, [string]$exe) {
    if ($hwnd -and $hwnd -gt 0) {
        try {
            $proc = Get-Process -Id ([int]$hwnd) -ErrorAction Stop
            if ($proc.Path) {
                $script:SessionLaunchCache[$exe.ToLowerInvariant()] = $proc.Path
                return $proc.Path
            }
        } catch { }
    }
    if (-not $exe) { return $null }
    $key = $exe.ToLowerInvariant()
    if ($script:SessionLaunchCache.ContainsKey($key)) { return $script:SessionLaunchCache[$key] }
    $name = [System.IO.Path]::GetFileNameWithoutExtension($exe)
    if (-not $name) { return $null }
    $proc = Get-Process -Name $name -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($proc -and $proc.Path) {
        $script:SessionLaunchCache[$key] = $proc.Path
        return $proc.Path
    }
    return $null
}

function Build-SessionWindow([int64]$hwnd, $windowMap) {
    if (-not $windowMap.ContainsKey($hwnd)) { return $null }
    $info = $windowMap[$hwnd]
    $exe = $info.exe
    if (-not $exe) { return $null }
    $win = [ordered]@{
        exe   = $exe
        title = $info.title
    }
    $launch = Get-LaunchPathForWindow $hwnd $exe
    if ($launch) { $win.launch = $launch }
    return $win
}

function Build-SessionLayoutPayload {
    if (-not (Test-Path $script:WorkspaceStateFile)) { return $null }
    if (-not (Get-Command lwm -ErrorAction SilentlyContinue)) { return $null }

    $wsState = Get-Content $script:WorkspaceStateFile -Raw | ConvertFrom-Json
    $windowMap = Get-WindowMapFromQuery

    $activeWorkspace = 2
    if ($wsState.active_workspace) {
        $vals = @($wsState.active_workspace.PSObject.Properties | ForEach-Object { [int]$_.Value })
        if ($vals.Count -gt 0) { $activeWorkspace = $vals[0] + 1 }
    }

    $workspaces = [System.Collections.Generic.List[object]]::new()
    foreach ($entry in @($wsState.workspaces)) {
        $index = [int]$entry.workspace_index + 1
        if ($index -lt 1 -or $index -gt 3) { continue }
        $columns = [System.Collections.Generic.List[object]]::new()
        foreach ($col in @($entry.workspace.columns)) {
            $windows = [System.Collections.Generic.List[object]]::new()
            foreach ($hwnd in @($col.windows)) {
                $win = Build-SessionWindow ([int64]$hwnd) $windowMap
                if ($win) { $windows.Add($win) }
            }
            if ($windows.Count -gt 0) {
                $columns.Add([ordered]@{ windows = $windows })
            }
        }
        if ($columns.Count -gt 0) {
            $workspaces.Add([ordered]@{ index = $index; columns = $columns })
        }
    }

    if ($workspaces.Count -eq 0) { return $null }

    return [ordered]@{
        version          = 1
        saved_at         = (Get-Date).ToUniversalTime().ToString('o')
        active_workspace = $activeWorkspace
        workspaces       = $workspaces
    }
}

function Get-SessionLayoutHash($payload) {
    if (-not $payload) { return '' }
    $parts = [System.Collections.Generic.List[string]]::new()
    $parts.Add("ws$($payload.active_workspace)")
    foreach ($ws in @($payload.workspaces)) {
        foreach ($col in @($ws.columns)) {
            foreach ($win in @($col.windows)) {
                $parts.Add("$($ws.index):$($win.exe):$($win.title)")
            }
        }
    }
    return ($parts -join '|')
}

function Write-SessionLayoutAtomic($payload) {
    if (-not $payload) { return }
    New-Item -ItemType Directory -Force -Path $script:SessionDataDir | Out-Null
    $tmp = "$script:SessionLayoutFile.tmp"
    ($payload | ConvertTo-Json -Depth 8 -Compress) | Set-Content -Path $tmp -Encoding UTF8 -NoNewline
    Move-Item -Path $tmp -Destination $script:SessionLayoutFile -Force
}

function Invoke-SessionLayoutSaveNow {
    $payload = Build-SessionLayoutPayload
    if (-not $payload) { return }
    $hash = Get-SessionLayoutHash $payload
    if ($hash -eq $script:SessionLastHash) { return }
    Write-SessionLayoutAtomic $payload
    $script:SessionLastHash = $hash
}

function Request-SessionLayoutSave {
    $script:SessionSaveDueAt = (Get-Date).AddSeconds(2)
}

function Try-FlushSessionLayoutSave {
    if (-not $script:SessionSaveDueAt) { return }
    if ((Get-Date) -lt $script:SessionSaveDueAt) { return }
    $script:SessionSaveDueAt = $null
    Invoke-SessionLayoutSaveNow
}

function Save-SessionLayout([switch]$Force) {
    if ($Force) {
        Invoke-SessionLayoutSaveNow
        return
    }
    Request-SessionLayoutSave
}

function Test-SessionLayoutJoin {
    param(
        $wsStateJson,
        $queryLines
    )
    $wsState = $wsStateJson | ConvertFrom-Json
    $windowMap = @{}
    foreach ($line in $queryLines) {
        if ($line -notmatch '^\s*(\d+)\s+-\s+(.+?)\s+\(([^)]*)\)') { continue }
        $windowMap[[int64]$Matches[1]] = @{ title = $Matches[2].Trim(); exe = $Matches[3].Trim() }
    }
    $found = 0
    foreach ($entry in @($wsState.workspaces)) {
        foreach ($col in @($entry.workspace.columns)) {
            foreach ($hwnd in @($col.windows)) {
                if ($windowMap.ContainsKey([int64]$hwnd) -and $windowMap[[int64]$hwnd].exe) { $found++ }
            }
        }
    }
    return $found
}

if ($MyInvocation.InvocationName -ne '.' -and $MyInvocation.Line -notmatch '^\s*\.') {
    $script:fail = 0
    $fixture = @'
{
  "workspaces": [
    {
      "workspace_index": 0,
      "workspace": { "columns": [ { "windows": [ 100 ] } ] }
    },
    {
      "workspace_index": 1,
      "workspace": { "columns": [ { "windows": [ 200 ] }, { "windows": [ 300 ] } ] }
    }
  ],
  "active_workspace": { "\\\\.\\DISPLAY1": 1 }
}
'@
    $lines = @(
        '  100 - Zen Browser (zen.exe) [col 0 win 0]',
        '  200 - Unknown () [col 0 win 0]',
        '  300 - Cursor Agents (Cursor.exe) [col 1 win 0]'
    )
    $joined = Test-SessionLayoutJoin $fixture $lines
    if ($joined -ne 2) {
        Write-Error "join expected 2 got $joined"
        $script:fail++
    }
    $payload = [ordered]@{
        version = 1
        saved_at = '2026-01-01T00:00:00Z'
        active_workspace = 2
        workspaces = @(
            [ordered]@{ index = 1; columns = @([ordered]@{ windows = @([ordered]@{ exe = 'zen.exe'; title = 'Zen' }) }) }
        )
    }
    $hash1 = Get-SessionLayoutHash $payload
    $hash2 = Get-SessionLayoutHash $payload
    if ($hash1 -ne $hash2 -or -not $hash1) {
        Write-Error 'hash unstable'
        $script:fail++
    }
    if ($script:fail -ne 0) { exit 1 }
    Write-Output 'save-session ok'
}
