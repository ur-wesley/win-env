$BarDir = Join-Path $env:APPDATA "leopardwm\bar"
$StatusFile = Join-Path $BarDir "status.json"
New-Item -ItemType Directory -Force -Path $BarDir | Out-Null
. (Join-Path $BarDir "strip-apps.ps1")
. (Join-Path $BarDir "save-session.ps1")

$script:SeenHwnds = [System.Collections.Generic.HashSet[int64]]::new()
$script:Placing = $false

$StripNames = @("browser", "main", "misc")

$state = [ordered]@{
    workspace     = "main"
    workspace_bar = "main browser misc"
    workspace_idx = 2
    app           = ""
    title         = ""
    column        = 0
    column_ui     = 1
    columns       = 0
    windows       = 0
    ws1_label     = "browser"
    ws2_label     = "main"
    ws3_label     = "misc"
    ws1_class     = "leopardwm-ws"
    ws2_class     = "leopardwm-ws-active"
    ws3_class     = "leopardwm-ws"
}

function Set-ColumnUi {
    $state.column_ui = [int]$state.column + 1
}

function Format-WsLabel([string]$name, [bool]$active) {
    $cls = if ($active) { 'ws-tab ws-tab-active' } else { 'ws-tab' }
    return "<span class='$cls'>$name</span>"
}

function Set-WorkspaceBar {
    $state.workspace_bar = ($StripNames -join " ")
    $idx = [array]::IndexOf($StripNames, $state.workspace)
    if ($idx -ge 0) { $state.workspace_idx = $idx + 1 }
    for ($i = 0; $i -lt $StripNames.Count; $i++) {
        $name = $StripNames[$i]
        $n = $i + 1
        $active = ($state.workspace_idx -eq $n)
        $state["ws${n}_label"] = Format-WsLabel $name $active
        $state["ws${n}_class"] = if ($active) { "leopardwm-ws-active" } else { "leopardwm-ws" }
    }
}

function Set-WindowsList {
    $all = (lwm query all 2>&1) | Out-String
    $items = [System.Collections.Generic.List[object]]::new()
    $tip = [System.Collections.Generic.List[string]]::new()
    foreach ($line in ($all -split "`n")) {
        if ($line -notmatch '^\s*(\d+)\s+-\s+(.+?)\s+\(([^)]+)\)') { continue }
        $hwnd = [int64]$Matches[1]
        $title = $Matches[2].Trim()
        $exe = $Matches[3].Trim()
        $focused = $line -match '\[FOCUSED\]'
        $col = 0
        if ($line -match '\[col (\d+)') { $col = [int]$Matches[1] + 1 }
        $app = Get-AppName $exe $line
        $items.Add([ordered]@{ hwnd = $hwnd; title = $title; app = $app; exe = $exe; column = $col; focused = $focused })
        $prefix = if ($focused) { '* ' } else { '  ' }
        $tip.Add("$prefix$app")
    }
    $state.windows_list = $items
    $state.windows_tip = ($tip -join "`n")
}

function Get-AppName([string]$executable, [string]$line) {
    if ($line -match '—\s+(.+?)\s+\([^)]+\)\s+\[col') {
        return $Matches[1].Trim()
    }
    if ($executable) {
        return [System.IO.Path]::GetFileNameWithoutExtension($executable)
    }
    return ""
}

function Save-Status {
    $json = ($state | ConvertTo-Json -Compress)
    $tmp = "$StatusFile.tmp"
    $utf8 = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($tmp, $json, $utf8)
    Move-Item -Path $tmp -Destination $StatusFile -Force
}

function Sync-FromQuery {
    $ws = (lwm query workspace 2>&1) | Out-String
    if ($ws -match 'Active workspace:\s*(\d+) \((.+)\)') {
        $state.workspace_idx = [int]$Matches[1]
        $state.workspace = $Matches[2]
        if ($state.workspace_idx -gt 3) { $null = lwm workspace 2 2>&1; $state.workspace_idx = 2; $state.workspace = 'main' }
        Set-WorkspaceBar
    } elseif ($ws -match 'Active workspace:\s*(\d+)') {
        $state.workspace_idx = [int]$Matches[1]
        if ($state.workspace_idx -gt 3) { $null = lwm workspace 2 2>&1; $state.workspace_idx = 2; $state.workspace = 'main' }
        $idx = $state.workspace_idx - 1
        if ($idx -ge 0 -and $idx -lt $StripNames.Count) {
            $state.workspace = $StripNames[$idx]
        }
        Set-WorkspaceBar
    }
    if ($ws -match 'Columns: (\d+)') { $state.columns = [int]$Matches[1] }
    if ($ws -match 'Windows: (\d+)') { $state.windows = [int]$Matches[1] }
    if ($ws -match 'Focused column: (\d+)') {
        $state.column = [int]$Matches[1]
        Set-ColumnUi
    }

    $all = (lwm query all 2>&1) | Out-String
    foreach ($line in ($all -split "`n")) {
        if ($line -match '\[FOCUSED\]') {
            if ($line -match '^\s*\d+ - (.+?) (?:\(|\[col)') {
                $state.title = $Matches[1].Trim()
            }
            if ($line -match '\(([^)]+)\)\s+\[col') {
                $state.app = Get-AppName $Matches[1] $line
            }
            break
        }
    }
    Set-WindowsList
    Request-SessionLayoutSave
    Try-FlushSessionLayoutSave
}

function Place-NewWindows {
    if ($script:Placing) { return }
    $moved = $false
    $script:Placing = $true
    try {
        foreach ($item in @($state.windows_list)) {
            if (-not $item.hwnd) { continue }
            if (-not $script:SeenHwnds.Add([int64]$item.hwnd)) { continue }
            if (Test-RetileExe $item.exe -or Test-LayoutRepairExe $item.exe) {
                Repair-TiledWindow ([int64]$item.hwnd) $item.exe $item.title
            }
            if (Test-StripClassified $item.exe $item.title) { continue }
            if ([int]$state.workspace_idx -eq 2) { continue }
            Move-HwndToStrip ([int64]$item.hwnd) 2 $item.exe
            $moved = $true
        }
        if ($moved) {
            $null = lwm workspace 2 2>&1
            $state.workspace_idx = 2
            $state.workspace = "main"
            Set-WorkspaceBar
        }
    } finally {
        $script:Placing = $false
    }
}

function Apply-Event($ev) {
    switch ($ev.type) {
        "workspace_changed" {
            if ($ev.name) { $state.workspace = $ev.name }
            if ($null -ne $ev.new_index) { $state.workspace_idx = [int]$ev.new_index + 1 }
            Set-WorkspaceBar
        }
        "focused_window_changed" {
            if ($ev.title) { $state.title = $ev.title }
            if ($ev.executable) { $state.app = Get-AppName $ev.executable $null }
        }
        "layout_changed" {
            $state.column = [int]$ev.focused_column
            Set-ColumnUi
            $state.columns = @($ev.columns).Count
            $count = 0
            foreach ($col in $ev.columns) { $count += @($col.window_ids).Count }
            $state.windows = $count
            Save-SessionLayout
        }
        "heartbeat" { Sync-FromQuery }
    }
    Set-WindowsList
    Place-NewWindows
    Try-FlushSessionLayoutSave
}

Sync-FromQuery
Set-WorkspaceBar
Set-WindowsList
foreach ($item in @($state.windows_list)) {
    if ($item.hwnd) { $null = $script:SeenHwnds.Add([int64]$item.hwnd) }
}
Save-Status
Save-SessionLayout -Force

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = "lwm"
$psi.Arguments = "subscribe --events workspace,focused_window,layout,heartbeat"
$psi.RedirectStandardOutput = $true
$psi.UseShellExecute = $false
$psi.CreateNoWindow = $true

while ($true) {
    $proc = [System.Diagnostics.Process]::Start($psi)
    try {
        while (-not $proc.StandardOutput.EndOfStream) {
            $line = $proc.StandardOutput.ReadLine()
            if (-not $line) { continue }
            try {
                Apply-Event ($line | ConvertFrom-Json)
                Save-Status
            } catch { }
        }
    } finally {
        if (-not $proc.HasExited) { $proc.Kill() }
        $proc.Dispose()
    }
    Sync-FromQuery
    Save-Status
    Start-Sleep -Seconds 2
}
