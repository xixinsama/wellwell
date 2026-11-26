# Platformer Debug 0.1.0

Optional, **read-only** runtime diagnostics for Platformer Kit games: a debug
HUD, collision/sensor/velocity visualisers, a pixel grid overlay, a minimap-style
debug map, TAS input record/replay, and live tuning hotkeys. Nothing here mutates
gameplay state except the explicit TAS input source and tuning hotkeys, which are
opt-in nodes.

## Compatibility

| Item | Value |
| --- | --- |
| Godot | 4.7 |
| Platformer Kit | 0.1.0 |
| Autoloads | none |
| Editor plugin | `addons/platformer_debug/plugin.cfg` (no editor UI; safe to disable, the runtime scenes are plain nodes) |

## Install

1. Enable `addons/platformer_debug/plugin.cfg` in **Project Settings → Plugins**.
2. Drop the nodes you want into a scene (see the table below).
3. For the shipped game wiring, `scenes/runtime/world_root.tscn` already contains
   `DebugOverlay` and `DebugHud`; `scenes/app/main.tscn` hosts the HUD-space
   `TasPanel`.

## Nodes

| Node / scene | Purpose | Main surface |
| --- | --- | --- |
| `DebugHud` (`runtime/debug_hud.tscn`) | Text HUD: state, velocity, sensors, room | `bind_player(player)`, `bind_subject(node)`, `set_section_enabled()`, `is_section_enabled()` |
| `DebugOverlay2D` (`runtime/debug_overlay_2d.tscn`) | Owner of the overlay + HUD + visualiser, one toggle | `set_enabled()`, `is_enabled()`, `bind_subject()`, `get_subject()`, `get_hud()`; exports `subject_path`, `hud_path`, `toggle_keycode` (F3), `start_enabled` |
| `PlatformerDebugVisualizer2D` | Draws collision boxes, sensor rays, relative/platform/world velocity | `bind_subject()`, `set_layer_enabled()`, `is_layer_enabled()`, `get_velocity_vectors()` |
| `GridOverlay` (`runtime/grid_overlay.tscn`) | Safe-frame and 8/16 px pixel grid | `toggle_grid()`; exports `safe_size`, `safe_origin`, colours |
| `DebugMap` (`runtime/debug_map.tscn`) | Flat chunk rectangle visualiser | `set_map_model(dictionary)`; exports colours, `chunk_pixel_size`, `offset` |
| `TasTool` (`runtime/tas_tool.tscn`) | Record/replay one input frame per physics tick, save/load JSON | `player_path`, `panel_path`, `slow_scale`, `recording_path` |
| `TasPanel` (`runtime/tas_panel.tscn`) | HUD-space status panel | `set_lines(lines)` |
| `PlatformerAutoRouteTool` (`runtime/autopilot_tool.gd`) | `F4` route mode: place a start and a goal, plan a jump/dash/climb route with the kit solver, then drive the character | `open_tool()`, `close_tool()`, `set_start(pos)`, `set_goal(pos)`, `plan_and_run()`, `get_status_line()`, `get_progress()` |
| `TuningHotkeys` | Runtime tuning with `[` / `]` / `-` / `=` | `player_path`, `step_ratio` |

### TAS controls

| Key | Action |
| --- | --- |
| `Ctrl+R` | start / stop recording |
| `Ctrl+P` | start / stop playback |
| `Ctrl+S` | save `user://tas_recording.json` (atomic write with `.tmp` + `.bak`) |
| `F6` / `F7` | step / rewind one frame |
| `F8` | clear |
| `F9` | half speed |
| `F10` | reset player to the recording start |
| `F11` | load the recording |

### Auto-route controls

| Key | Action |
| --- | --- |
| `F4` | open / close route mode (closing restores manual input) |
| arrows / `WASD` | move the 8 px cursor (`Shift` moves four cells) |
| `Space` | pin the start |
| `X` | pin the goal |
| `Enter` / `Z` | plan and run |
| `Backspace` | clear both pins and the route |
| `Esc` | close route mode |

The tool scans the current room once, when it opens (a sliced, visible sweep;
tile one-way platforms are read from their physics polygons), then plans with the
kit's `AutopilotPlanner` on a worker thread (the frame never stalls) and replays
the route through `AutopilotDriver`; a drift larger than 10 px triggers a replan
from where the character stands. Changing rooms closes the tool and drops the
raster, so nothing is built while walking between rooms.
See `docs/systems/auto-route.md`.

`TasInputSource` wraps the player's normal input source and is independent of the
player class (it only needs `set_input_source()` / `get_input_source()`).

## Tests

```powershell
godot --headless --path . -s res://tests/run_runtime_suite.gd -- --group=platformer_debug
# the same two files individually
godot --headless --path . -s res://tests/run_test_script.gd -- res://tests/platformer_debug/test_debug_contract.gd
godot --headless --path . -s res://tests/run_test_script.gd -- res://tests/platformer_debug/test_tas.gd
```

## Known limits

- The overlay only reads `get_debug_state()`. If a subject does not expose it, the
  HUD shows blanks rather than guessing.
- TAS records the movement intent (axes, jump edges, dash), not raw mouse or UI
  input; playback is deterministic only at the same physics tick rate.
- Hotkeys are `_unhandled_input` listeners: a focused UI control that consumes the
  key will win.
- The saved recording is a plain JSON file (`version: 1`); loading accepts any
  dictionary frames, so a hand-edited file with bad types degrades to neutral
  intents instead of failing loudly.
