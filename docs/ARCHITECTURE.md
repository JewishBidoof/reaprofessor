# Architecture

## Layers

```
┌─────────────────────────────────────────────┐
│  ReaProfessor panels (Lua gfx / optional UI)│  Cue List · Snapshots · Chain Rack
├─────────────────────────────────────────────┤
│  Live Mode + screensets + theme             │  Presentation / focus
├─────────────────────────────────────────────┤
│  SWS / ReaPack / native ReaScript API       │  Snapshots, actions, ExtState
├─────────────────────────────────────────────┤
│  REAPER host + JACK/ASIO/CoreAudio          │  Audio, MIDI, VST3/LV2
└─────────────────────────────────────────────┘
```

## Data model

Show state lives **in the project** so `.RPP` files are portable:

- `P_EXT:ReaProfessor` ExtState keys for cues, snapshot metadata, UI prefs
- Optional SWS snapshot slots for track/FX chunk recall
- Markers/regions can mirror cue positions for timeline sync later

### Cue record

```lua
{
  id = "cue_001",
  name = "Song 2 - Verse",
  kind = "snapshot",   -- snapshot | midi | osc | action | compound
  payload = { snapshot = "Verse A" },
  notes = "",
}
```

### Snapshot record

Stores selected track FX parameter values (and optionally mute/solo/bypass) as JSON in ExtState. Heavy full-chunk recall can delegate to SWS when available.

## Script entry points

| Script | Role |
| --- | --- |
| `ReaProfessor.lua` | Hub: open panels, live mode, about |
| `cue_list.lua` | Cue editor + GO engine |
| `snapshots.lua` | Capture / recall / list |
| `chain_rack.lua` | Per-track chain overview |
| `live_mode.lua` | Toggle live presentation |
| `lib/*.lua` | Shared UI, data, OSC helpers |

## Cloud / CI testing

`tools/smoke_test.sh` launches REAPER with a Lua harness that:

1. Confirms version + resource path
2. Confirms SWS + ReaPack APIs
3. Loads ReaProfessor modules and runs a dry cue GO
4. Writes `/tmp/reaprofessor-test/smoke-result.txt` and quits
