# Development setup

## Cloud agent environment

This repo ships `.cursor/environment.json`:

- **install** — `tools/install_dev_env.sh` (REAPER, SWS, ReaPack, JACK, ALSA utils, Lua)
- **start** — `tools/start_jack.sh` (dummy JACK server for audio I/O without hardware)

The desktop session already exposes `DISPLAY=:1` (TigerVNC + noVNC) so REAPER GUI scripts can be exercised visually.

## Local link into REAPER

```bash
./tools/link_to_reaper.sh
```

Creates:

- `~/.config/REAPER/Scripts/ReaProfessor` → `scripts/ReaProfessor`
- `~/.config/REAPER/ColorThemes/ReaProfessor.ReaperTheme` → theme file

On Windows/macOS, set `REAPER_RESOURCE` to your resource path before linking.

## Theme workflow

1. Edit `theme/ReaProfessor.ReaperTheme` for colors/fonts
2. For WALTER layouts, unpack Default 7.0 as a base (see `tools/unpack_default_theme.sh`) and iterate `rtconfig.txt`
3. Reload theme in REAPER: switch away/back, or action **Theme Development: Reload**

## Script workflow

1. Edit Lua under `scripts/ReaProfessor/`
2. Re-run from Actions, or bind a shortcut to the hub script
3. Use `reaper.ShowConsoleMsg` / the smoke harness for automation

## Audio without hardware

```bash
./tools/start_jack.sh
# REAPER Preferences → Audio Device → JACK (8 in / 8 out dummy)
```
