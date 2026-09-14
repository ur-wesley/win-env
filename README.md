# win-env

LeopardWM tiling + YASB status bar for Windows.

## Setup

```powershell
git clone https://github.com/ur-wesley/win-env.git "$env:APPDATA\leopardwm"
cd "$env:APPDATA\leopardwm"
powershell -ExecutionPolicy Bypass -File .\setup.ps1
```

`setup.ps1` installs LeopardWM and YASB via winget, links YASB config into `%USERPROFILE%\.config\yasb`, wires autostart, and hides the Windows taskbar.

## Remove

```powershell
powershell -ExecutionPolicy Bypass -File .\remove.ps1
```

Stops YASB and bar helpers, removes autostart entries, drops the YASB junction (restores `~\.config\yasb.bak` if present), and shows the Windows taskbar. Does not uninstall packages or delete config files. Add `-StopLeopardwm` to also stop the tiling daemon.

Optional ISO week numbers in YASB calendar (needs admin + Python):

```powershell
powershell -ExecutionPolicy Bypass -File .\setup.ps1 -PatchCalendar
```

## Cheatsheet

**`%APPDATA%\leopardwm\config\CHEATSHEET.md`**

## Day-to-day

| Task | Command |
|------|---------|
| Reload YASB | `yasbc reload` |
| Hide taskbar | `powershell -File "$env:APPDATA\leopardwm\bar\hide-taskbar.ps1"` |
| Show taskbar | `powershell -File "$env:APPDATA\leopardwm\bar\show-taskbar.ps1"` |
| Emergency revert | `Win+Ctrl+Escape` then show taskbar |

## Layout

- LeopardWM config: `%APPDATA%\leopardwm\config\config.toml`
- YASB config (junction): `%USERPROFILE%\.config\yasb` → `%APPDATA%\leopardwm\yasb`
- Bar scripts: `%APPDATA%\leopardwm\bar\`

See [`bar/README.md`](bar/README.md) for bar internals.
