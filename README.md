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
3. **Actions → Show action list** → search `ReaProfessor` → run **ReaProfessor**

> ReaProfessor is opened from the **Actions** list. It does **not** add an Extensions menu item — editing `reaper-menu.ini` nested ReaPack/SWS under a submenu. If a previous build did that, open the hub and click **Restore Extensions menu**.

See [docs/REAPACK.md](docs/REAPACK.md) for publishing details.



```bash
# Install REAPER + SWS + ReaPack + JACK (Linux cloud/dev)
./tools/install_dev_env.sh

# Symlink this repo into your REAPER resource path
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
theme/                  Live-oriented color theme overlay
resources/              Demo project, OSC map stubs
tools/                  Install, link, jack, smoke tests
docs/                   Feature map + architecture
tests/                  Automated REAPER script checks
.cursor/                Cloud agent environment config
```

## Status

Active development (v0.3.8):

- Snapshot recall fixed for real show use: always stores FXCHAIN; Recall uses snap mode; params auto-rebuilds
- `+ CUE` captures **full** FX state; default snapshot mode is full
- LiveProfessor-inspired UI (Cue List GO NEXT, Global Snapshots, Chains)
- Full snapshot recall restores complete multi-FX / JSFX chains
- Actions-list entry only — does **not** customize Extensions (keeps ReaPack/SWS top-level)
- Hub button **Restore Extensions menu** undoes any prior nesting from older builds
- Show/project actions enabled
- 1:1 channel creator, custom MIDI/OSC mapping
- ReaPack metapackage under `Live/ReaProfessor.lua` (auto-publish workflow remains disabled)

```bash
./tools/link_to_reaper.sh
```

