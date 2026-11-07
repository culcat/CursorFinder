# CursorFinder (`culcat.cursor-finder`)

macOS-style **"Shake mouse pointer to locate"** plugin for **Omarchy** (`omarchy-shell` / Hyprland).

When you rapidly shake the mouse back and forth, the cursor smoothly scales up into a crisp high-DPI vector pointer so you can immediately spot it on large or multi-monitor setups, then smoothly shrinks back when you stop.

---

## Features / Возможности

- **macOS-accurate Shake Detection**: Tracks directional pointer strokes and rapid direction reversals over a sliding window — ignores normal fast flicks across the screen while triggering immediately on genuine back-and-forth shakes.
- **Razor-Sharp Vector Overlay**: Renders a high-DPI vector cursor (`QtQuick.Shapes` `CurveRenderer`) on a click-through `WlrLayer.Overlay` surface across all monitors. Works consistently over Wayland native apps, XWayland, Electron, browsers, and terminals without the ~60ms compositor freeze caused by `hyprctl setcursor`.
- **Zero Idle Overhead**: Communicates directly with Hyprland's UNIX socket (`.socket.sock`) using adaptive polling (`25 Hz` idle, `83 Hz` moving, `125 Hz` while enlarged) and emits zero QML updates until a shake occurs.
- **Built-in Settings Panel & CLI IPC**: Includes an interactive Omarchy settings panel (`Panel.qml`) and full `omarchy-shell cursor-finder` IPC controls.

---

## Installation / Установка

Install and enable directly via Omarchy's plugin manager:

```bash
omarchy plugin add git@github.com:culcat/CursorFinder.git --enable
```

Or via HTTPS:

```bash
omarchy plugin add https://github.com/culcat/CursorFinder.git --enable
```

Update at any time:

```bash
omarchy plugin update culcat.cursor-finder
```

---

## Usage & IPC Commands / Управление

Open the interactive settings panel:

```bash
omarchy-shell cursor-finder settings
# or:
omarchy-shell shell toggle culcat.cursor-finder '{}'
```

Trigger a manual locate pulse (can also be bound to a hotkey in `~/.config/hypr/bindings.lua`):

```bash
omarchy-shell cursor-finder locate
```

Check status or change settings from the terminal:

```bash
omarchy-shell cursor-finder status
omarchy-shell cursor-finder toggle
omarchy-shell cursor-finder set sensitivity 1.4
omarchy-shell cursor-finder set maxScale 5.0
omarchy-shell cursor-finder set cursorStyle theme   # macos | theme | inverted
omarchy-shell cursor-finder set showHalo true
```

---

## Configuration / Конфигурация

Settings are persisted automatically in `~/.config/omarchy/cursor-finder.json` (and mirrored inline in `~/.config/omarchy/shell.json`):

```json
{
  "enabled": true,
  "sensitivity": 1.0,
  "maxScale": 4.2,
  "baseSize": 24,
  "holdMs": 480,
  "cursorStyle": "macos",
  "showHalo": false,
  "hideNativeCursor": true
}
```
