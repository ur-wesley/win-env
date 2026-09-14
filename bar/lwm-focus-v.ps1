param(
    [Parameter(Mandatory)][ValidateSet('up', 'down')]$Direction,
    [switch]$Move,
    [switch]$SelfTest
)

function Get-QueryField([string]$Text, [string]$Name) {
    if ($Text -match "${Name}:\s*(\d+)") { return [int]$Matches[1] }
    return 0
}

function Get-VerticalAction([string]$Dir, [bool]$IsMove, [int]$Ws, [int]$Win, [int]$StackCount) {
    if ($Dir -eq 'up') {
        if ($Win -gt 0) { return $(if ($IsMove) { 'move-up' } else { 'focus-up' }) }
        if ($Ws -gt 1) { return $(if ($IsMove) { "move-ws:$($Ws - 1)" } else { "focus-ws:$($Ws - 1)" }) }
        return 'noop'
    }
    if ($Win + 1 -lt $StackCount) { return $(if ($IsMove) { 'move-down' } else { 'focus-down' }) }
    if ($Ws -lt 3) { return $(if ($IsMove) { "move-ws:$($Ws + 1)" } else { "focus-ws:$($Ws + 1)" }) }
    return 'noop'
}

function Invoke-VerticalAction([string]$Action) {
    switch -Regex ($Action) {
        '^focus-up$' { $null = lwm focus up 2>&1 }
        '^focus-down$' { $null = lwm focus down 2>&1 }
        '^move-up$' { $null = lwm move-window up 2>&1 }
        '^move-down$' { $null = lwm move-window down 2>&1 }
        '^focus-ws:(\d+)$' { $null = lwm workspace ([int]$Matches[1]) 2>&1 }
        '^move-ws:(\d+)$' {
            $target = [int]$Matches[1]
            $null = lwm move-to-workspace $target 2>&1
            $null = lwm workspace $target 2>&1
        }
    }
}

if ($SelfTest) {
    $fail = 0
    function Assert-Action([string]$label, [string]$got, [string]$want) {
        if ($got -ne $want) {
            Write-Error "$label -> $got want $want"
            $script:fail++
        }
    }
    Assert-Action 'focus up stack' (Get-VerticalAction 'up' $false 2 1 3) 'focus-up'
    Assert-Action 'focus up strip' (Get-VerticalAction 'up' $false 2 0 1) 'focus-ws:1'
    Assert-Action 'focus up clamp' (Get-VerticalAction 'up' $false 1 0 1) 'noop'
    Assert-Action 'focus down stack' (Get-VerticalAction 'down' $false 2 0 3) 'focus-down'
    Assert-Action 'focus down strip' (Get-VerticalAction 'down' $false 2 1 1) 'focus-ws:3'
    Assert-Action 'focus down clamp' (Get-VerticalAction 'down' $false 3 0 1) 'noop'
    Assert-Action 'move up stack' (Get-VerticalAction 'up' $true 2 1 3) 'move-up'
    Assert-Action 'move up strip' (Get-VerticalAction 'up' $true 2 0 1) 'move-ws:1'
    Assert-Action 'move up clamp' (Get-VerticalAction 'up' $true 1 0 1) 'noop'
    Assert-Action 'move down stack' (Get-VerticalAction 'down' $true 2 0 3) 'move-down'
    Assert-Action 'move down strip' (Get-VerticalAction 'down' $true 2 1 1) 'move-ws:3'
    Assert-Action 'move down clamp' (Get-VerticalAction 'down' $true 3 0 1) 'noop'
    if ($fail -ne 0) { exit 1 }
    Write-Output 'lwm-focus-v ok'
    exit 0
}

$wsText = (lwm query workspace 2>&1) | Out-String
$ws = Get-QueryField $wsText 'Active workspace'
if ($ws -lt 1 -or $ws -gt 3) { $null = lwm workspace 2 2>&1; $ws = 2 }

$focused = (lwm query focused 2>&1) | Out-String
$col = Get-QueryField $focused 'Column index'
$win = Get-QueryField $focused 'Window index'

$stackCount = 1
$all = (lwm query all 2>&1) | Out-String
foreach ($m in [regex]::Matches($all, "\[col $col win (\d+)\]")) {
    $idx = [int]$m.Groups[1].Value + 1
    if ($idx -gt $stackCount) { $stackCount = $idx }
}

$action = Get-VerticalAction $Direction $Move.IsPresent $ws $win $stackCount
if ($action -ne 'noop') { Invoke-VerticalAction $action }
