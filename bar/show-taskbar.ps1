Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarAl" -Value 1

Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class LwmShell {
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern IntPtr FindWindow(string lpClassName, string lpWindowName);
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll")]
    public static extern bool SystemParametersInfo(uint uiAction, uint uiParam, ref RECT pvParam, uint fWinIni);
    [DllImport("user32.dll")]
    public static extern int GetSystemMetrics(int nIndex);
    public const uint SPI_SETWORKAREA = 0x002F;
    public const uint SPIF_SENDCHANGE = 0x02;
    public const int SM_CXSCREEN = 0;
    public const int SM_CYSCREEN = 1;
}
"@

foreach ($class in @("Shell_TrayWnd", "Shell_SecondaryTrayWnd")) {
    $hwnd = [LwmShell]::FindWindow($class, $null)
    if ($hwnd -ne [IntPtr]::Zero) {
        [LwmShell]::ShowWindow($hwnd, 5) | Out-Null
    }
}

$rect = New-Object LwmShell+RECT
$rect.Left = 0
$rect.Top = 0
$rect.Right = [LwmShell]::GetSystemMetrics([LwmShell]::SM_CXSCREEN)
$rect.Bottom = [LwmShell]::GetSystemMetrics([LwmShell]::SM_CYSCREEN) - 48
[LwmShell]::SystemParametersInfo([LwmShell]::SPI_SETWORKAREA, 0, [ref]$rect, [LwmShell]::SPIF_SENDCHANGE) | Out-Null

lwm refresh 2>$null
lwm reload 2>$null
