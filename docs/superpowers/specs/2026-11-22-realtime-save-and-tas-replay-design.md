# Realtime Save and TAS Replay Design

Date: 2026-11-22
Status: Approved for implementation

## Summary

Add two player-facing systems:

1. **Realtime Save** (实时存档): a Game settings toggle that resumes the player
   at the exact position and velocity where the previous session ended.
2. **TAS Replay** (回放): recording and playback of a run through the existing
   debug-overlay input TAS, driven by familiar shortcuts: `Ctrl+R` to
   start/stop recording, `Ctrl+P` to play/stop playback, and `Ctrl+S` to save
   the current recording.

The realtime feature extends the existing save snapshot rather than replacing
checkpoints. The replay feature extends the existing TAS tool; it does not add
a second recording pipeline or a ghost actor.

## Goals

- A new Game setting, **Realtime Save**, off by default.
- With it enabled, the player returns to the same room and the same
  position/velocity after quitting and relaunching, even after a crash (at most
  about two seconds of progress lost).
- Death still respawns at the last checkpoint or room spawn. Realtime Save must
  never turn death into a free rewind.
- `Ctrl+R` toggles recording, `Ctrl+P` plays/stops the recorded run, and
  `Ctrl+S` saves the current recording.
- Replay works with the existing debug overlay TAS and keeps its old `F5`-`F12`
  shortcuts working.
- The setting is localized in English and Simplified Chinese.

## Non-goals

- No translucent ghost actor or side-by-side "Super Meat Boy" race view.
- No per-level replay library, timestamped archives, or replay browser UI.
- No rollback of puzzle/collectible/entity state to an arbitrary earlier
  moment. Realtime Save only adds the player's live transform to the existing
  snapshot; entity states continue to use their current saved values.
- No new save slot, menu page, or autosave indicator.
- No change to checkpoint activation, kill zones, or normal respawn rules.

## Existing Context

- `PlatformerSaveManager` owns a `SaveSnapshot` per slot and writes it through
  `SaveStorage` (JSON with a `.backup.json` fallback).
- `WorldSession.start()` loads the snapshot, stages terrain, and calls
  `WorldRuntime.setup_session()`, which currently spawns the player at the
  snapshot's respawn point.
- `SaveSnapshot` stores `world_id`, `current_room_id`, respawn identity, entity
  states, and module states.
- `TasInputSource` records one `CharacterIntent` per physics tick and replays
  it. `TasTool` already owns start/stop/play/save/load and the debug panel.
- `GlobalSettings` is the game-layer settings service and already applies
  toggles immediately through `settings_changed`.

## Setting

Add a `SettingsDefinition.toggle` to the **Game** section:

| Field | Value |
| --- | --- |
| key | `realtime_save_enabled` |
| label key | `SETTINGS_REALTIME_SAVE` |
| description key | `SETTINGS_DESC_REALTIME_SAVE` |
| default | `false` |
| node name | `RealtimeSaveToggle` |

`WellwellGlobalSettingsManager` gets:

```gdscript
func is_realtime_save_enabled() -> bool
func set_realtime_save_enabled(enabled: bool) -> void
```

English label: `Realtime Save`.
English description: `Resume at the exact spot where you left, even after
quitting; death still returns to the last checkpoint.`
Chinese label: `实时存档`.
Chinese description: `退出后从离开时的精确位置继续；死亡仍回到最近的检查点。`

The setting is intentionally off by default so existing saves and existing
checkpoint behavior do not change until the player opts in.

## Snapshot Data

Extend `SaveSnapshot` with optional resume data:

```gdscript
var has_resume := false
var resume_position := Vector2.ZERO
var resume_velocity := Vector2.ZERO

func set_resume_state(position: Vector2, velocity: Vector2) -> bool
func clear_resume_state() -> void
```

`set_resume_state()` rejects non-finite positions or velocities and does not
mutate existing data on rejection.

Serialized JSON adds one optional object; the format version stays `1` so older
game builds can still read the rest of the save:

```json
"player_resume": {
  "position": {"x": 120.0, "y": 64.0},
  "velocity": {"x": 0.0, "y": 0.0}
}
```

When no resume data exists, `player_resume` is `{}` or omitted. On load, a
missing, malformed, or non-finite `player_resume` is ignored; the snapshot
still loads and falls back to the normal spawn path. This keeps old saves and
hand-edited JSON from blocking startup.

`PlatformerSaveManager` gains two convenience methods so game code does not
reach into snapshot internals:

```gdscript
func set_resume_state(position: Vector2, velocity: Vector2, immediate := false) -> bool
func clear_resume_state(immediate := false) -> bool
```

They update `current_snapshot`, then either `queue_commit()` or `commit()`
immediately. They return `false` when there is no selected snapshot.

## Realtime Save Service

New game-layer node: `scripts/save/realtime_save_service.gd`
(`class_name RealtimeSaveService`), instantiated as a child of `WorldRoot` in
`scenes/runtime/world_root.tscn`.

Responsibilities:

- Resolve the player (`../Player`), the parent `WorldSession`, `/root/SaveManager`,
  and `/root/GlobalSettings`.
- Stay idle until `WorldSession.world_ready` fires and the setting is enabled.
- Every `2.0` seconds while active, capture the player's global position and
  `velocity`, and write them to the active snapshot through
  `SaveManager.set_resume_state()`.
- Capture immediately when the setting is turned on and after `world_ready`.
- On `NOTIFICATION_WM_CLOSE_REQUEST` and in `_exit_tree`, perform a final
  capture and `commit()` so a normal quit is exact.
- When the setting is turned off, clear resume data from the active snapshot
  and commit immediately.
- Skip writes when position and velocity are unchanged, so an idle game does
  not write the slot every two seconds.
- Do nothing if the player, session, save manager, or snapshot is unavailable.
  A failed disk write leaves the previous slot intact; there is no modal error
  and no warning spam.

No autoload is added. The service lives and dies with the gameplay scene, which
keeps menu-only sessions from touching save data.

### Setting Off Is Authoritative

If the setting is off, a snapshot that still contains old `player_resume` data
must not resume there. `MainMenu._start_game()` clears `player_resume` on the
prepared snapshot before starting the world when the setting is off. This
covers the "disable it in the menu, then continue an old save" path before
`WorldSession` ever reads the snapshot.

During gameplay, disabling the setting makes the service clear the active
snapshot immediately. Re-enabling starts capturing again from the current
position.

## Restoring the Exact Spot

`WorldRuntime.setup_session()` gains a resume path:

1. Only consider resume data when `snapshot.world_id` matches the world being
   started and `snapshot.has_resume` is true.
2. Convert the saved global position into runtime-local space and resolve its
   room with `WorldData.get_room_id_at_world_position()`. If no room contains
   it, or the position/velocity is non-finite, ignore the resume data and use
   the existing respawn path.
3. Use the resume position's chunk instead of the room origin chunk when
   staging resident rooms, then stage/trim rooms exactly as the spawn path
   does.
4. Do not align the staged world to the checkpoint spawn in this path.
5. Restore the player through `PlayerController.resume_at(position, velocity,
   checkpoint_position)` (or a generic fallback on players that do not expose
   it).
6. Keep `current_room_id` and tracking consistent with the restored position.

`PlayerController.resume_at()` restores the transform and velocity while
preserving the death respawn:

```gdscript
func resume_at(pos: Vector2, restored_velocity: Vector2, checkpoint_position: Vector2) -> void:
    respawn_at(pos)
    spawn_position = checkpoint_position if checkpoint_position.is_finite() else spawn_position
    velocity = restored_velocity
    _world_velocity = restored_velocity
```

`checkpoint_position` comes from `snapshot.respawn_position` when the snapshot
has a respawn room. If it does not, the player's current spawn position is
kept. Death, kill zones, and checkpoint activation therefore continue to use
the checkpoint, not the live position.

Transient movement state (an in-progress dash, wall grab, ladder ride, or
water state) is not serialized. The position and linear velocity are restored;
the player re-enters normal movement on the next physics tick. This is
intentional: live save is a session resume, not a frame-perfect rollback.

## TAS Replay

`TasTool` is the only new control surface. `TasInputSource` already records one
intent per physics tick and replays it, so it does not need a second format.

### Shortcuts

| Shortcut | Action |
| --- | --- |
| `Ctrl+R` | Start recording if idle; stop recording if recording. |
| `Ctrl+P` | Start playback if idle; stop playback if playing. |
| `Ctrl+S` | Stop recording if recording, then save the current clip. |
| `F6` / `F7` / `F10` | Existing aliases for record / play / save. |
| `F5`, `F8`, `F9`, `F11`, `F12` | Existing panel, clear, slow-motion, load, reset. |

The TAS panel text is updated to show the `Ctrl` shortcuts. The panel remains
small and inside the existing overlay.

### Recording

- Starting a recording clears the frame buffer, stops playback, and records
  from the player's **current** position. It does not teleport the player back
  to an older recording's start.
- The start position, world id, and current room id are captured when recording
  starts.
- Stopping recording keeps the frames and leaves the player where they are.
- Starting again replaces the previous clip, matching the existing TAS
  behavior.

### Playback

- `Ctrl+P` with frames available resets the player to the recording start and
  begins replaying inputs through `TasInputSource`.
- Pressing `Ctrl+P` again while playing stops playback and returns control to
  the real input source.
- When the last frame is consumed, `TasInputSource` emits
  `playback_finished`; the panel reports `playback finished` and live input is
  restored.
- If the current world/room differs from where the clip was recorded, playback
  is refused with a status line naming the required room. This avoids
  teleporting the player into a room that is not loaded.

### Saving and Loading

- `Ctrl+S` writes to the existing fixed path `user://tas_recording.json`,
  overwriting the previous clip.
- Payload:

```json
{
  "version": 1,
  "physics_ticks": 120,
  "start": [120.0, 64.0],
  "world_id": "main_world",
  "room_id": "room_00_00",
  "frames": []
}
```

- `F11` / load keeps working. `world_id` and `room_id` are optional on load so
  old recordings still play; when present, they feed the room guard.
- A save/open failure updates the TAS status line and leaves the previous file
  untouched.

## Error Handling

- Invalid resume JSON or a position outside every room: ignore resume data and
  spawn normally.
- Off-screen/deleted player or no active snapshot: realtime service no-ops.
- Setting off: clear stale resume data at menu start and on toggle.
- Replay with no frames: status `nothing recorded`.
- Replay in another room/world: refuse with a clear status line.
- `Ctrl+S` with no frames: save an empty clip is allowed but the status reports
  `saved 0 frames`; playback then reports `nothing recorded`.
- No new `WARNING:` or `ERROR:` output during a clean boot.

## Tests

Add or extend:

- `tests/save/test_save_codec.gd`: resume data round-trips; invalid resume data
  is ignored without rejecting the snapshot; clearing removes it.
- `tests/save/test_save_slots.gd`: manager helpers update the active snapshot
  and honor immediate versus queued commits.
- `tests/save/test_realtime_save.gd`: service captures only while enabled,
  clears on disable, skips unchanged transforms, and flushes immediately on
  exit.
- `tests/world/test_world_runtime.gd`: `setup_session()` restores position and
  velocity from resume data, keeps the checkpoint spawn, and falls back to the
  spawn path for invalid data.
- `tests/platformer_debug/test_tas_tool_hotkeys.gd`: `Ctrl+R` starts/stops,
  `Ctrl+P` starts/stops, `Ctrl+S` saves, and old `F` aliases still map to the
  same actions.
- `tests/ui/test_settings_pages.gd`: the catalog contains
  `realtime_save_enabled`, it lives in Game, defaults to off, and builds its
  toggle row.
- `tests/runtime_suite.gd`: register the new test scripts.

Manual verification:

1. Boot with the setting off: existing checkpoint behavior is unchanged.
2. Enable the setting, move to a non-checkpoint spot, quit, relaunch, continue
   the slot: the player appears at that spot.
3. Die: the player returns to the checkpoint, not the live position.
4. Disable the setting, quit, relaunch: the player returns to the checkpoint.
5. Record a short run with `Ctrl+R`, stop it, save with `Ctrl+S`, play it with
   `Ctrl+P`; verify the player repeats the movement and `Ctrl+P` stops it.
6. Try playing the clip from another room; verify the panel refuses with the
   room name.

## Documentation

- `docs/controls.md`: TAS shortcuts, including `Ctrl+R` / `Ctrl+P` / `Ctrl+S`
  and the retained `F` aliases.
- `README.md`: mention realtime save and replay in the feature list.
- `CHANGELOG.md`: add the realtime save setting and replay shortcuts.
- `docs/project-structure.md`: mention `scripts/save/realtime_save_service.gd`.
- `localization/menu.csv` plus regenerated `.translation` files for the new
  setting strings.

## Acceptance Criteria

- The Game settings page shows **Realtime Save** with localized label and
  description; it is off by default and applies immediately.
- With the setting on, position and velocity are captured at most every two
  seconds and on quit; relaunching restores the same room and spot.
- Death still uses the checkpoint.
- `Ctrl+R`, `Ctrl+P`, and `Ctrl+S` perform record toggle, play toggle, and save
  respectively; `F6`, `F7`, and `F10` still work.
- Replay refuses to start in the wrong room instead of breaking world state.
- Focused tests pass, touched scripts pass `--check-only`, and the full suite
  reports no new failures compared with the baseline.
