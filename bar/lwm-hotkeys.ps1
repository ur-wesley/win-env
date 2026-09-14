$mutex = New-Object System.Threading.Mutex($false, 'Global\LeopardWM-Bar-Hotkeys')
if (-not $mutex.WaitOne(0)) { exit 0 }

Add-Type -AssemblyName System.Windows.Forms

$BarDir = Join-Path $env:APPDATA "leopardwm\bar"
$FocusScript = (Join-Path $BarDir "lwm-focus-v.ps1").Replace('\', '\\')
$RetileScript = (Join-Path $BarDir "lwm-retile-focus.ps1").Replace('\', '\\')
$LogFile = Join-Path $BarDir "hotkeys.log"

if (-not ([System.Management.Automation.PSTypeName]'LwmBarHotkeys').Type) {
    $typeDef = @"
using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows.Forms;
public class LwmBarHotkeys : Form {
    const int WM_HOTKEY = 0x0312;
    const int WH_MOUSE_LL = 14;
    const int WH_KEYBOARD_LL = 13;
    const int WM_MOUSEWHEEL = 0x020A;
    const int WM_MOUSEHWHEEL = 0x020E;
    const int WM_KEYDOWN = 0x0100;
    const int WM_SYSKEYDOWN = 0x0104;
    const int VK_R = 0x52;
    const int LLMHF_INJECTED = 0x01;
    const int GESTURE_THRESHOLD = 360;
    const int GESTURE_TIMEOUT_MS = 300;
    const int NAV_COOLDOWN_MS = 150;
    static readonly string FocusScript = @"$FocusScript";
    static readonly string RetileScript = @"$RetileScript";
    static readonly string LogFile = @"$($LogFile.Replace('\','\\'))";
    bool registered;
    IntPtr mouseHook = IntPtr.Zero;
    IntPtr keyboardHook = IntPtr.Zero;
    LowLevelMouseProc mouseProc;
    LowLevelKeyboardProc keyboardProc;
    int swipeAccumX, swipeAccumY;
    long swipeLastEventMs;
    long cooldownUntilMs;
    long retileCooldownUntilMs;
    readonly Stopwatch clock = Stopwatch.StartNew();
    [StructLayout(LayoutKind.Sequential)]
    struct POINT { public int x, y; }
    [StructLayout(LayoutKind.Sequential)]
    struct MSLLHOOKSTRUCT {
        public POINT pt;
        public int mouseData;
        public int flags;
        public int time;
        public IntPtr dwExtraInfo;
    }
    delegate IntPtr LowLevelMouseProc(int nCode, IntPtr wParam, IntPtr lParam);
    delegate IntPtr LowLevelKeyboardProc(int nCode, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll")] static extern bool RegisterHotKey(IntPtr hWnd, int id, int fsModifiers, int vk);
    [DllImport("user32.dll")] static extern short GetAsyncKeyState(int vKey);
    [DllImport("user32.dll")] static extern bool UnregisterHotKey(IntPtr hWnd, int id);
    [DllImport("user32.dll")] static extern IntPtr SetWindowsHookEx(int idHook, LowLevelMouseProc lpfn, IntPtr hMod, uint dwThreadId);
    [DllImport("user32.dll", EntryPoint = "SetWindowsHookEx")] static extern IntPtr SetKeyboardHookEx(int idHook, LowLevelKeyboardProc lpfn, IntPtr hMod, uint dwThreadId);
    [DllImport("user32.dll")] static extern bool UnhookWindowsHookEx(IntPtr hhk);
    [DllImport("user32.dll")] static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);
    void Log(string msg) {
        try { File.AppendAllText(LogFile, DateTime.Now.ToString("HH:mm:ss") + " " + msg + Environment.NewLine); } catch { }
    }
    void RegisterKeys() {
        if (registered) return;
        registered = true;
        if (!RegisterHotKey(Handle, 1, 3, 0x26)) Log("fail Up");
        if (!RegisterHotKey(Handle, 2, 3, 0x28)) Log("fail Down");
        if (!RegisterHotKey(Handle, 3, 3, 0x4B)) Log("fail K");
        if (!RegisterHotKey(Handle, 4, 3, 0x4A)) Log("fail J");
        if (!RegisterHotKey(Handle, 6, 7, 0x26)) Log("fail Shift+Up");
        if (!RegisterHotKey(Handle, 7, 7, 0x28)) Log("fail Shift+Down");
        if (!RegisterHotKey(Handle, 8, 7, 0x4B)) Log("fail Shift+K");
        if (!RegisterHotKey(Handle, 9, 7, 0x4A)) Log("fail Shift+J");
        Log("registered on hwnd " + Handle);
    }
    void RegisterGestures() {
        mouseProc = MouseHookProc;
        mouseHook = SetWindowsHookEx(WH_MOUSE_LL, mouseProc, IntPtr.Zero, 0);
        if (mouseHook == IntPtr.Zero) Log("fail gesture hook");
        else Log("gesture hook registered");
    }
    void RegisterKeyboardHook() {
        keyboardProc = KeyboardHookProc;
        keyboardHook = SetKeyboardHookEx(WH_KEYBOARD_LL, keyboardProc, IntPtr.Zero, 0);
        if (keyboardHook == IntPtr.Zero) Log("fail keyboard hook");
        else Log("keyboard hook registered");
    }
    void DispatchRetile() {
        long now = NowMs();
        if (now < retileCooldownUntilMs) return;
        retileCooldownUntilMs = now + 500;
        Log("retile hotkey");
        RunScript(RetileScript, "");
    }
    IntPtr KeyboardHookProc(int nCode, IntPtr wParam, IntPtr lParam) {
        if (nCode >= 0) {
            int msg = wParam.ToInt32();
            if (msg == WM_KEYDOWN || msg == WM_SYSKEYDOWN) {
                int vk = Marshal.ReadInt32(lParam);
                if (vk == VK_R) {
                    bool ctrl = (GetAsyncKeyState(0x11) & 0x8000) != 0;
                    bool alt = (GetAsyncKeyState(0x12) & 0x8000) != 0;
                    bool shift = (GetAsyncKeyState(0x10) & 0x8000) != 0;
                    if (ctrl && alt && !shift) {
                        DispatchRetile();
                        return (IntPtr)1;
                    }
                }
            }
        }
        return CallNextHookEx(keyboardHook, nCode, wParam, lParam);
    }
    long NowMs() { return clock.ElapsedMilliseconds; }
    IntPtr MouseHookProc(int nCode, IntPtr wParam, IntPtr lParam) {
        if (nCode >= 0) {
            int msg = wParam.ToInt32();
            bool horizontal = msg == WM_MOUSEHWHEEL;
            bool vertical = msg == WM_MOUSEWHEEL;
            if (horizontal || vertical) {
                var hookStruct = (MSLLHOOKSTRUCT)Marshal.PtrToStructure(lParam, typeof(MSLLHOOKSTRUCT));
                int delta = (short)((hookStruct.mouseData >> 16) & 0xFFFF);
                if ((hookStruct.flags & LLMHF_INJECTED) != 0) {
                    long now = NowMs();
                    if (swipeLastEventMs != 0 && now - swipeLastEventMs > GESTURE_TIMEOUT_MS) {
                        swipeAccumX = 0;
                        swipeAccumY = 0;
                    }
                    swipeLastEventMs = now;
                    if (now < cooldownUntilMs) return (IntPtr)1;
                    if (horizontal) swipeAccumX += delta;
                    else swipeAccumY += delta;
                    string gesture = null;
                    if (horizontal && Math.Abs(swipeAccumX) >= GESTURE_THRESHOLD) {
                        gesture = swipeAccumX > 0 ? "right" : "left";
                        swipeAccumX = 0;
                    } else if (vertical && Math.Abs(swipeAccumY) >= GESTURE_THRESHOLD) {
                        gesture = swipeAccumY > 0 ? "down" : "up";
                        swipeAccumY = 0;
                    }
                    if (gesture != null) {
                        cooldownUntilMs = now + NAV_COOLDOWN_MS;
                        DispatchGesture(gesture);
                        return (IntPtr)1;
                    }
                }
            }
        }
        return CallNextHookEx(mouseHook, nCode, wParam, lParam);
    }
    void DispatchGesture(string dir) {
        switch (dir) {
            case "left": RunLwm("focus left"); break;
            case "right": RunLwm("focus right"); break;
            case "up": RunScript(FocusScript, " -Direction up"); break;
            case "down": RunScript(FocusScript, " -Direction down"); break;
        }
    }
    void RunLwm(string args) {
        Process.Start(new ProcessStartInfo {
            FileName = "lwm",
            Arguments = args,
            UseShellExecute = false,
            CreateNoWindow = true
        });
    }
    protected override void OnHandleCreated(EventArgs e) {
        base.OnHandleCreated(e);
        RegisterKeys();
        RegisterGestures();
        RegisterKeyboardHook();
    }
    protected override void OnFormClosed(FormClosedEventArgs e) {
        for (int id = 1; id <= 9; id++) UnregisterHotKey(Handle, id);
        if (keyboardHook != IntPtr.Zero) {
            UnhookWindowsHookEx(keyboardHook);
            keyboardHook = IntPtr.Zero;
        }
        if (mouseHook != IntPtr.Zero) {
            UnhookWindowsHookEx(mouseHook);
            mouseHook = IntPtr.Zero;
        }
        base.OnFormClosed(e);
    }
    void RunScript(string path, string args) {
        string lwmBin = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles) + "\\LeopardWM\\bin";
        string pathEnv = Environment.GetEnvironmentVariable("PATH") ?? "";
        var psi = new ProcessStartInfo {
            FileName = "powershell.exe",
            Arguments = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File \"" + path + "\"" + args,
            UseShellExecute = false,
            CreateNoWindow = true
        };
        psi.Environment["PATH"] = lwmBin + ";" + pathEnv;
        Process.Start(psi);
    }
    protected override void WndProc(ref Message m) {
        if (m.Msg == WM_HOTKEY) {
            int id = m.WParam.ToInt32();
            bool move = id >= 6;
            bool up = id == 1 || id == 3 || id == 6 || id == 8;
            string args = " -Direction " + (up ? "up" : "down");
            if (move) args += " -Move";
            RunScript(FocusScript, args);
            return;
        }
        base.WndProc(ref m);
    }
}
"@
    Add-Type -TypeDefinition $typeDef -ReferencedAssemblies System.Windows.Forms
}

$form = New-Object LwmBarHotkeys
$form.WindowState = 'Minimized'
$form.ShowInTaskbar = $false
$form.Show() | Out-Null
[System.Windows.Forms.Application]::Run($form)
