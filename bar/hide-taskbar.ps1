Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarAl" -Value 0

& (Join-Path $env:APPDATA "leopardwm\bar\refresh-workarea.ps1")

& (Join-Path $env:APPDATA "leopardwm\bar\sync-outer-gap.ps1")
lwm reload 2>$null
