# LiveProfessor 2 → ReaProfessor feature map

Target: make REAPER feel like a dedicated live plugin host instead of a studio DAW.

Open via **Extensions → ReaProfessor** (native `hookcustommenu` extension) or Actions.
Child windows use **← Back** to return to the hub.
Gfx UI is HiDPI-aware (`gfx.ext_retina`).
Do not customize `[Main extensions]` in `reaper-menu.ini` — that nests every other extension under Default menu.

## Priority 1 — Show control + live I/O (current)

| Feature | LP2 behavior | ReaProfessor approach |
| --- | --- | --- |
| Cue List | Ordered cues with nested actions, fade/pre/post, GO NEXT, Edit/Armed | `cue_list.lua` — hierarchical actions + inspector |
| Global Snapshots | Store/recall whole show; filter; fire cue | `snapshots.lua` — full FXCHAIN + fire-cue link |
| Navigator | Overview of all plugins | `navigator.lua` |
| Live Mode | Perform surface | `live_mode.lua` — next/on-deck + GO + chains |
| 1:1 channel setup | Quick rack of inputs | `create_channels.lua` — N mono in→HW out |
| Record while processing | Multitrack dry + live FX | **Same strip** or **double patch** |
| OSC / MIDI | Hardware + show control | **Mapping** editor; control service |
| Signal Chains | Serial plugin racks | `chain_rack.lua` horizontal nodes |

## Record-safe processing

Processing must never alter what hits the multitrack:

1. **Same strip** — `I_RECMODE=input` (dry file) + `I_RECMON=on` (hear FX) + mono HW out. Snapshots edit FX on that strip.
2. **Double patch** — `CH## REC` armed, no monitor/HW out; `CH## FX` same input, monitor + FX + HW out. Snapshots **skip** `role=record` tracks.

## Snapshot modes

| Mode | Capture | Recall |
| --- | --- | --- |
| `bypass` | Always stores full FXCHAIN + params | Enable/bypass only (auto-rebuilds if chain missing) |
| `params` | Always stores full FXCHAIN + params | Apply params by FX identity; **rebuilds chain** if plugins differ |
| `full` | Always stores full FXCHAIN + params | Restore exact FXCHAIN (fallback: AddByName + params) |

Default mode is **full**. Cue `+ CUE` always captures full. The Snapshots UI Recall button uses each snapshot’s own stored mode (does not override with the filter selector).

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
