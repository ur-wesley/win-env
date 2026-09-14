# LeopardWM status bar (YASB)

Waybar-style top bar wired to LeopardWM via `lwm subscribe`.

## Files

| File | Purpose |
|------|---------|
| `lwm-status.ps1` | Bridge: streams LWM events → `status.json` |
| `status.json` | Live state (title, column, workspace) — read by YASB |
| `start-bar.ps1` | Autostart: bridge → wait 2s → YASB |
| `read-status.cmd` | YASB reads `status.json` (avoids broken PS path expansion) |
| `lwm-ws.ps1` / `lwm-ws-cycle.ps1` | Bar click → switch strip (clamped 1–3) |
| `lwm-focus-v.ps1` | Stack-then-strip navigation (Up/Down/K/J + swipe up/down) |
| `lwm-hotkeys.ps1` | `Ctrl+Alt` Up/Down/K/J + 3-finger swipe gestures |
| `lwm-cycle-window.ps1` | Bar title click → cycle windows on current strip |
| `refresh-workarea.ps1` | Hide taskbar + force full-screen work area (runs on login) |
| `sync-outer-gap.ps1` | Reload LWM config + refresh (applies `outer_gap_top` from config.toml) |
| `repair-all-tiled.ps1` | Reload + repair Electron/chromium tiles (Cursor, Antigravity, Zed) |
| `hide-taskbar.ps1` | Same as refresh-workarea + reload LWM config |
| `show-taskbar.ps1` | Restore Windows taskbar + work area |

YASB config: `%USERPROFILE%\.config\yasb\` (`config.yaml`, `styles.css`)

## Bar layout

Three YASB bars across the top:

| Bar | Widgets |
|-----|---------|
| Left (`lwm-bar-left`) | Workspace tabs, focused app, column index, pomodoro, media |
| Center (`lwm-bar-center`) | Clock |
| Right (`lwm-bar-right`) | Traffic, RAM, CPU, Wi-Fi, Bluetooth, battery, volume, systray, power menu, control center |

Bar reserved height: **36px** (YASB bar bottom at y=36: 4 top pad + 32 height) — matches `outer_gap_top` in LeopardWM `config.toml`.

## Autostart order

1. `LeopardWM` — `%ProgramFiles%\LeopardWM\bin\leopardwm.exe` (existing Run key)
2. `LeopardWM-Bar` — `start-bar.ps1` (bridge + YASB)

## Hide / restore Windows taskbar

**Before hiding:** confirm tray icons (Discord, etc.) appear in YASB systray.

```powershell
# Hide (auto-hide + HWND hide)
powershell -ExecutionPolicy Bypass -File "$env:APPDATA\leopardwm\bar\hide-taskbar.ps1"

# Restore
powershell -ExecutionPolicy Bypass -File "$env:APPDATA\leopardwm\bar\show-taskbar.ps1"
```

Or: Settings → Personalization → Taskbar → automatically hide taskbar.

**Emergency:** `Win+Ctrl+Escape` (LeopardWM panic) then run `show-taskbar.ps1` or toggle taskbar in Settings.

## Manual start / stop

```powershell
# Bridge only
powershell -WindowStyle Hidden -ExecutionPolicy Bypass -File "$env:APPDATA\leopardwm\bar\lwm-status.ps1"

# YASB
& "C:\Program Files\YASB\yasb.exe"
yasbc reload
yasbc stop
```

## Troubleshooting

- Bar covers tiles / gap under bar / misaligned windows → run `repair-all-tiled.ps1` or focus window + `Ctrl+Alt+R`
- Stale title/column → check `status.json`; restart bridge
- Systray missing icons → restart YASB after those apps; some apps ignore `TaskbarCreated` (NVIDIA App)
