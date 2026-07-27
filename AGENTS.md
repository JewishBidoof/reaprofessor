# ReaProfessor — Cloud / agent notes

## What this repo is

REAPER theme + ReaScript pack to approximate **LiveProfessor 2** (live VST host with cue lists, snapshots, signal chains).

## Environment

- `.cursor/environment.json` installs REAPER 7.x, SWS, ReaPack, JACK, and links scripts into `~/.config/REAPER`.
- `tools/start_jack.sh` keeps a dummy JACK server alive (no audio hardware required).
- GUI is available on `DISPLAY=:1` (VNC). Prefer scripted smoke tests for verification.

MIDI/OSC bindings are empty until configured in **Mapping**.

## Verify changes

```bash
./tools/link_to_reaper.sh
./tools/smoke_test.sh
```

Manual UI check: `reaper -nosplash` then Actions → load `Scripts/ReaProfessor/ReaProfessor.lua`.

## Conventions

- Lua scripts under `scripts/ReaProfessor/`; shared code in `lib/`.
- Persist show data in project ExtState via `lib/data.lua` (portable with `.RPP`).
- Prefer amber/stage dark UI — avoid purple “AI slop” palettes in gfx panels.
- Do not commit REAPER userdata (`~/.config/REAPER`) or large unpacked Default theme PNGs; unpack via `tools/unpack_default_theme.sh`.
