# LiveProfessor 2 → ReaProfessor feature map

Target: make REAPER feel like a dedicated live plugin host instead of a studio DAW.

## Priority 1 — Show control (MVP)

| Feature | LP2 behavior | ReaProfessor approach |
| --- | --- | --- |
| Cue List | Ordered cues: recall snapshot, send MIDI, map controller, OSC | `cue_list.lua` stores cues in project ExtState; GO / Back / Jump |
| Global Snapshots | Store/recall whole show state | `snapshots.lua` + optional SWS snapshot actions |
| Live Mode | Focus on racks + cues, not arrange | `live_mode.lua` toggles mixer/TCP visibility, transport, screenset |
| Signal Chains | Serial plugin racks per source | One REAPER track = one chain; `chain_rack.lua` overview |

## Priority 2 — Routing & control

| Feature | LP2 behavior | ReaProfessor approach |
| --- | --- | --- |
| Wire View | Free patching between plugins | Native track routing matrix + pin connector; future gfx patch bay |
| Hardware Controllers | MIDI/OSC maps with scaling | REAPER MIDI learn + OSC config in `resources/osc/` |
| OSC API | `/GlobalSnapshots/Recall`, `/CueLists/Go`, … | Scripted OSC listener mirroring LP2 path names where practical |
| LTC / timecode | Cue triggers from LTC | REAPER timecode + marker/region actions (later) |

## Priority 3 — Presentation

| Feature | LP2 behavior | ReaProfessor approach |
| --- | --- | --- |
| Dark live UI | Stage-readable, low glare | `theme/ReaProfessor.ReaperTheme` color overlay |
| View Sets | Named window layouts | REAPER screensets saved under `resources/screensets/` |
| Plugin / snapshot panels | Dedicated browser windows | gfx panels first; ReaImGui optional later |

## Non-goals (for now)

- Replacing REAPER's audio engine or plugin scanner
- Full AU parity on Linux (use VST3/LV2)
- Bit-identical LP2 project import (document manual migration instead)
