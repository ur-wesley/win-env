Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarAl" -Value 0 -ErrorAction SilentlyContinue

$stuckKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StuckRects3"
if (Test-Path $stuckKey) {
    $settings = (Get-ItemProperty $stuckKey -Name Settings -ErrorAction SilentlyContinue).Settings
    if ($settings -and $settings.Length -gt 12) {
        $settings[8] = 3
        Set-ItemProperty -Path $stuckKey -Name Settings -Value $settings
    }
}

Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class LwmWorkArea {
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern IntPtr FindWindow(string lpClassName, string lpWindowName);
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)]
    public struct APPBARDATA {
        public int cbSize;
        public IntPtr hWnd;
        public uint uCallbackMessage;
        public uint uEdge;
        public RECT rc;
        public int lParam;
    }
    [DllImport("shell32.dll")]
    public static extern uint SHAppBarMessage(uint dwMessage, ref APPBARDATA pData);
    [DllImport("user32.dll")]
    public static extern bool SystemParametersInfo(uint uiAction, uint uiParam, ref RECT pvParam, uint fWinIni);
    [DllImport("user32.dll")]
    public static extern int GetSystemMetrics(int nIndex);
    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern IntPtr SendMessageTimeout(IntPtr hWnd, int msg, IntPtr wParam, string lParam, int flags, int timeout, out IntPtr result);
    public const uint SPI_SETWORKAREA = 0x002F;
    public const uint SPIF_SENDCHANGE = 0x02;
    public const int SM_CXSCREEN = 0;
    public const int SM_CYSCREEN = 1;
    public const uint ABM_SETSTATE = 0x0000000a;
}
"@

$tray = [LwmWorkArea]::FindWindow("Shell_TrayWnd", $null)
if ($tray -ne [IntPtr]::Zero) {
    $abd = New-Object LwmWorkArea+APPBARDATA
    $abd.cbSize = 40
    $abd.hWnd = $tray
    $abd.lParam = 1
    [LwmWorkArea]::SHAppBarMessage([LwmWorkArea]::ABM_SETSTATE, [ref]$abd) | Out-Null
    [LwmWorkArea]::ShowWindow($tray, 0) | Out-Null
}

foreach ($class in @("Shell_SecondaryTrayWnd")) {
    $hwnd = [LwmWorkArea]::FindWindow($class, $null)
    if ($hwnd -ne [IntPtr]::Zero) {
        [LwmWorkArea]::ShowWindow($hwnd, 0) | Out-Null
    }
}

$rect = New-Object LwmWorkArea+RECT
$rect.Left = 0
$rect.Top = 0
$rect.Right = [LwmWorkArea]::GetSystemMetrics([LwmWorkArea]::SM_CXSCREEN)
$rect.Bottom = [LwmWorkArea]::GetSystemMetrics([LwmWorkArea]::SM_CYSCREEN)
[LwmWorkArea]::SystemParametersInfo([LwmWorkArea]::SPI_SETWORKAREA, 0, [ref]$rect, [LwmWorkArea]::SPIF_SENDCHANGE) | Out-Null

foreach ($msg in @("Environment", "TraySettings", "ShellState")) {
    $result = [IntPtr]::Zero
    [LwmWorkArea]::SendMessageTimeout([IntPtr]0xFFFF, 0x001A, [IntPtr]::Zero, $msg, 2, 1000, [ref]$result) | Out-Null
}

lwm refresh 2>$null
& (Join-Path $env:APPDATA "leopardwm\bar\sync-outer-gap.ps1")
& (Join-Path $env:APPDATA "leopardwm\bar\repair-all-tiled.ps1")
