param(
    [int]$Target = 2
)

. (Join-Path $PSScriptRoot 'strip-apps.ps1')

function Move-AllWindowsOff([int]$FromWs, [int]$ToWs) {
    if ($FromWs -eq $ToWs) { return }
    $null = lwm workspace $FromWs 2>&1
    $guard = 0
    while ($guard++ -lt 64) {
        $all = (lwm query all 2>&1) | Out-String
        if ($all -match 'Managed Windows \(0 total\)') { return }
        $null = lwm focus start 2>&1
        $before = (lwm query all 2>&1) | Out-String
        $null = lwm move-to-workspace $ToWs 2>&1
        $after = (lwm query all 2>&1) | Out-String
        if ($before -eq $after) { return }
    }
}

foreach ($ws in 9, 8, 7, 6, 5, 4) {
    Move-AllWindowsOff $ws $Target
}

Place-ManagedWindows
