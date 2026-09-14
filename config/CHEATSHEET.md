# LeopardWM cheat sheet

Three strips top → bottom: **browser** (1) · **main** (2) · **misc** (3). No wrap past browser or misc.

| Base | Meaning |
|------|---------|
| `Ctrl+Alt` | Focus / navigate / resize (WASD) |
| `Ctrl+Alt+Shift` | Reorder |
| `Ctrl+Alt+Win` | Monitor scope |

## Focus — `Ctrl+Alt` + arrows / HJKL

| Key | Action |
|-----|--------|
| `Ctrl+Alt+Left` / `Right` / `H` / `L` | Focus column left / right |
| `Ctrl+Alt+Up` / `Down` / `K` / `J` | Focus up/down in column; at stack edge jump strip above/below |
| `Ctrl+Alt+Home` / `End` | Focus first / last column |

Stack on **main**, focus on bottom window: `Up` → window above, `Up` again → **browser**.

## Gestures — 3-finger swipe

Same navigation as focus keys above (handled by `lwm-hotkeys.ps1`):

| Swipe | Action |
|-------|--------|
| Left / right | Focus column left / right |
| Up / down | Focus up/down in column; at stack edge jump strip above/below |

No wrap past browser (top) or misc (bottom).

## Reorder — `Ctrl+Alt+Shift` + arrows / HJKL

| Key | Action |
|-----|--------|
| `Ctrl+Alt+Shift+Left` / `Right` / `H` / `L` | Move column left / right on strip |
| `Ctrl+Alt+Shift+Up` / `Down` / `K` / `J` | Move window up / down in column; at stack edge move to strip above / below |
| `Ctrl+Alt+Shift+Home` / `End` | Column to start / end of strip |
| `Ctrl+Alt+Shift+Q` / `E` | Pop window to new column |
| `Ctrl+Alt+Shift+,` / `.` | Merge neighbor column into focused |

## Resize — `Ctrl+Alt` + WASD

| Key | Action |
|-----|--------|
| `Ctrl+Alt+A` / `D` | Column width narrower / wider |
| `Ctrl+Alt+W` / `S` | Window height taller / shorter (stacked columns only) |
| `Ctrl+Alt+0` | Equalize column widths |
| `Ctrl+Alt+Shift+0` | Equalize heights in column |

## Column layout

| Key | Action |
|-----|--------|
| `Ctrl+Alt+C` | Center column |
| `Ctrl+Alt+M` | Maximize column |

## Window modes

| Key | Action |
|-----|--------|
| `Ctrl+Alt+X` | Close focused window |
| `Ctrl+Alt+F` | Toggle floating |
| `Ctrl+Alt+Shift+F` | Toggle fullscreen |
| `Ctrl+Alt+T` | Toggle tabbed column |
| `Ctrl+Alt+\`` | Toggle scratchpad |
| `Ctrl+Alt+Shift+\`` | Stash to scratchpad |
| `Ctrl+Alt+Y` | Toggle sticky |
| `Ctrl+Alt+R` | Retile focused window |
| `Ctrl+Alt+P` | Toggle pause |

## Monitors — `Ctrl+Alt+Win`

| Key | Action |
|-----|--------|
| `Ctrl+Alt+Win+,` / `.` / arrows | Focus monitor left / right / up / down |
| `Ctrl+Alt+Win+Shift+,` / `.` / arrows | Move window to monitor |

## Workspaces

| Key | Action |
|-----|--------|
| `Alt+Tab` / `Ctrl+Alt+Space` | Toggle overview (arrows + Enter inside; each press toggles) |
| `Ctrl+Alt+1` / `2` / `3` | Jump to browser / main / misc |
| `Ctrl+Alt+Shift+R` | Reload config |
| `Win+Ctrl+Escape` | Emergency panic revert |

## YASB bar (click)

| Widget | Click |
|--------|-------|
| `browser` / `main` / `misc` | Left = switch strip (`[name]` = active); middle / right = overview |
| Title (app name) | Left / right = prev / next strip; middle = overview |
| `col N/M` | Left / right = focus column; middle = overview |

## CLI

```powershell
lwm query workspace
lwm workspace 2
lwm reload
powershell -File "$env:APPDATA\leopardwm\bar\migrate-workspaces.ps1"
```

Config: `%APPDATA%\leopardwm\config\config.toml`
