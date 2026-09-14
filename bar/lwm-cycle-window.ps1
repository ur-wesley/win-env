$all = (lwm query all 2>&1) | Out-String
$focused = (lwm query focused 2>&1) | Out-String
$curHwnd = 0
if ($focused -match 'Window ID:\s*(\d+)') { $curHwnd = [int]$Matches[1] }

$ids = @()
foreach ($line in ($all -split "`n")) {
    if ($line -match '^\s*(\d+)\s+-') { $ids += [int]$Matches[1] }
}
if ($ids.Count -eq 0) { return }

$idx = [array]::IndexOf($ids, $curHwnd)
$next = if ($idx -lt 0) { $ids[0] } else { $ids[($idx + 1) % $ids.Count] }

& (Join-Path $PSScriptRoot 'lwm-focus-window.ps1') -Hwnd $next
