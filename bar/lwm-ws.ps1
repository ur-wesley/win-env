param(
    [Parameter(Mandatory)][ValidateRange(1, 3)][int]$Number
)
$null = lwm workspace $Number 2>&1
