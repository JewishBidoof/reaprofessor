# ReaProfessor

Live-oriented REAPER theme and script pack that aims to replace **LiveProfessor 2** for live sound, theatre, and broadcast plugin hosting.

REAPER already hosts VST/VST3 (and LV2 on Linux), has deep routing, and is scriptable. ReaProfessor layers a LiveProfessor-style workflow on top:

| LiveProfessor 2 | ReaProfessor (REAPER) |
| --- | --- |
| Signal Chains | Tracks as chains + FX chain UI |
| Wire / matrix routing | Track I/O + sends + routing matrix |
| Global / plugin snapshots | ExtState snapshots + SWS snapshots |
| Cue Lists | ReaProfessor Cue List panel |
| MIDI / OSC / LTC | REAPER MIDI + OSC + script bridges |
| View Sets | Screensets + Live Mode action |
| Hardware controllers | MIDI learn / CSI / OSC maps |

## Requirements

- REAPER 7.x (Linux/macOS/Windows)
- [SWS/S&M Extension](https://www.sws-extension.org/) (recommended)
- [ReaPack](https://reapack.com/) (recommended)

## Install (ReaPack)

```
https://github.com/JewishBidoof/reaprofessor/raw/main/index.xml
```

1. **Extensions → ReaPack → Import a repository…** → paste URL → OK  
2. **Extensions → ReaPack → Browse packages…** → filter **ReaProfessor** (category **Live**) → Install  
3. **File → Quit** and reopen (loads `reaper_reaprofessor` from UserPlugins)  
4. **Extensions → ReaProfessor** (or Actions → ReaProfessor)

The Extensions entry is a **native** `hookcustommenu` plugin — the same API ReaPack/SWS use. It does **not** edit `reaper-menu.ini`, so your other extensions stay top-level siblings.

If an older 0.4.0/0.4.1 build nested everything under “Default menu”, open the hub once (clears that hijack), then quit/reopen.

See [docs/REAPACK.md](docs/REAPACK.md) for publishing details.

```bash
# Install REAPER + SWS + ReaPack + JACK (Linux cloud/dev)
./tools/install_dev_env.sh

# Symlink this repo + install native Extensions plugin into UserPlugins
./tools/link_to_reaper.sh

# Start dummy JACK (headless / no audio interface)
./tools/start_jack.sh

# Smoke-test scripting + extensions
./tools/smoke_test.sh
```

In REAPER: **Actions → Show action list → ReaScript: Load** →  
`Scripts/ReaProfessor/ReaProfessor.lua`

## Repo layout

```
scripts/ReaProfessor/   Lua UI + show-control scripts
native/                 hookcustommenu extension (Extensions → ReaProfessor)
dist/                   Prebuilt extension binaries
theme/                  Live-oriented color theme overlay
resources/              Demo project, OSC map stubs
tools/                  Install, link, jack, smoke tests
docs/                   Feature map + architecture
tests/                  Automated REAPER script checks
.cursor/                Cloud agent environment config
```

## Status

Active development (v0.4.6):

- **Extensions → ReaProfessor** via native `hookcustommenu` (no `reaper-menu.ini` hijack)
- Older 0.4.0/0.4.1 menu.ini customizations are cleared on hub open / startup
- ← Back navigation between hub and pages
- HiDPI / Retina gfx scaling for crisp UI on M3 Mac
- LiveProfessor 2–style Cue List, Navigator, Live Mode, Global Snapshots
- Snapshot recall stores full FXCHAIN; params auto-rebuilds
- 1:1 channel creator, custom MIDI/OSC mapping
- ReaPack metapackage under `Live/ReaProfessor.lua` (auto-publish workflow remains disabled)

```bash
./tools/link_to_reaper.sh
# macOS without CI binary: make -C native OS=Darwin && copy dylib into UserPlugins/
```
