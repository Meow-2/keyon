# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

`keyon` is an AutoHotkey v2 Windows hotkey manager. It supports: app window management (launch, focus, cycle), IME state switching, window control (close/cycle), and key remapping. All behavior is driven by INI config files — no hotkeys are hardcoded in AHK source.

## Commands

**Run (interpreted):**
```ps1
& "$env:USERPROFILE\scoop\apps\autohotkey\current\v2\AutoHotkey64.exe" .\keyon.ahk
```

**Syntax check only (no GUI, exits immediately):**
```ps1
& "$env:USERPROFILE\scoop\apps\autohotkey\current\v2\AutoHotkey64.exe" /ErrorStdOut .\keyon.ahk --check
```

**Compile to `keyon.exe` and restart:**
```ps1
.\scripts\compile.bat
```

**Enable/disable startup task:**
```ps1
.\scripts\enableAutoStartup.bat   # creates scheduled task \keyon\keyon at login
.\scripts\disableAutoStartup.bat
```

## Architecture

### Entry point: `keyon.ahk`
Instantiates all managers in order and calls `registerHotkeys()` on each. The `--check` flag causes immediate exit after loading, enabling syntax validation without running.

### Manager pattern
Each feature is a class in `lib/`:

| File | Class | Config source |
|------|-------|---------------|
| `appWindowManager.ahk` | `appWindowManager` | `config/apps.ini` |
| `imeManager.ahk` | `imeManager` | `config/ime.ini` |
| `infoManager.ahk` | `infoManager` | `config/wintools.ini` (`[windowInfo]`) |
| `windowControlManager.ahk` | `windowControlManager` | `config/wintools.ini` (`[windowControl]`) |
| `keyMapManager.ahk` | `keyMapManager` | `config/keymap.ini` |

All managers use `configReader` (`lib/configReader.ahk`) for INI access — it handles missing files, missing keys, and type coercion (bool/number/text) without throwing.

### `appWindowManager` hotkey logic
On hotkey trigger: find visible windows → cycle them; find hidden/minimized windows → restore and focus; find background process (`processName` + `wakeHotkey`) → wake; else → launch `target`. Uses `shellRun` (via `Shell.Application`) to launch apps at non-admin privilege even when `keyon.exe` runs elevated.

### AHK hotkey syntax in config
`#` = Win, `!` = Alt, `^` = Ctrl, `+` = Shift. Combinations: `#!n` = Win+Alt+N. Prefix-key combos: `Esc & a`.

## Spec document

`prompt/keyon.md` is the authoritative spec. Update it before changing behavior, then sync the code.

## Agent instructions (from AGENTS.md)

- Think in English, respond to the user in Chinese unless asked otherwise. Code comments in Chinese.
- Answer with the McKinsey Pyramid Principle: conclusion first, then supporting points, then details.
- Development environment: Windows 11, PowerShell default, WSL2 available.
- Do not invent undocumented behavior; mark unknown items as pending.
