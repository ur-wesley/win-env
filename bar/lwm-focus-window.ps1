param(
    [Parameter(Mandatory)][int]$Hwnd
)

Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class LwmWin32 {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
}
"@

$ptr = [IntPtr]$Hwnd
if ([LwmWin32]::IsIconic($ptr)) { [LwmWin32]::ShowWindow($ptr, 9) | Out-Null }
[LwmWin32]::SetForegroundWindow($ptr) | Out-Null
