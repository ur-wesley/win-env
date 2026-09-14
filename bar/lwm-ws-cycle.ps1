param(
    [Parameter(Mandatory)][ValidateSet('prev', 'next')]$Direction
)

$ws = (lwm query workspace 2>&1) | Out-String
$cur = 2
if ($ws -match 'Active workspace:\s*(\d+)') { $cur = [int]$Matches[1] }

$next = switch ($Direction) {
    'prev' { [Math]::Max(1, $cur - 1) }
    'next' { [Math]::Min(3, $cur + 1) }
}

if ($next -ne $cur) { $null = lwm workspace $next 2>&1 }
