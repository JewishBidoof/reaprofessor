# LiveProfessor 2 → ReaProfessor feature map

Target: make REAPER feel like a dedicated live plugin host instead of a studio DAW.

## Priority 1 — Show control + live I/O (current)

| Feature | LP2 behavior | ReaProfessor approach |
| --- | --- | --- |
| Cue List | Ordered cues: recall snapshot, send MIDI, map controller, OSC | `cue_list.lua` + `lib/commands.lua` |
| Global Snapshots | Store/recall whole show state | `snapshots.lua` with **bypass / params / full FX reload** modes |
| 1:1 channel setup | Quick rack of inputs | `create_channels.lua` — N mono in→HW out |
| Record while processing | Multitrack dry + live FX | **Same strip** (record input / monitor FX) or **double patch** (REC + FX tracks) |
| OSC / MIDI | Hardware + show control | **Mapping** editor — user-defined only (no defaults); control service |
| Live Mode | Focus on racks + cues | `live_mode.lua` |
| Signal Chains | Serial plugin racks | Tracks as chains; `chain_rack.lua` |

## Record-safe processing

Processing must never alter what hits the multitrack:

1. **Same strip** — `I_RECMODE=input` (dry file) + `I_RECMON=on` (hear FX) + mono HW out. Snapshots edit FX on that strip.
2. **Double patch** — `CH## REC` armed, no monitor/HW out; `CH## FX` same input, monitor + FX + HW out. Snapshots **skip** `role=record` tracks.

## Snapshot modes

| Mode | Capture | Recall |
| --- | --- | --- |
| `bypass` | FX enable states (+ mute/solo) | Enable/bypass only |
| `params` | Bypass + parameter values | Apply params (FX must already exist) |
| `full` | Full chain identity + params | Delete FX, re-add by name, apply params |

## OSC addresses (control service)

Suggested paths are listed in Mapping → OSC → Suggested path. **Nothing is active until you add a binding.**

Oneshoot bridge (after you map the path): set ExtState `ReaProfessor` / `osc_cmd` to your mapped path (optional `osc_arg`).

## Priority 2 — later

| Feature | Approach |
| --- | --- |
| Wire / matrix view | gfx patch bay on top of native routing |
| Native UDP OSC | Small bridge → ExtState queue, or CSI |
| LTC / timecode cues | Markers + timecode actions |
| View Sets | Screensets under `resources/screensets/` |
