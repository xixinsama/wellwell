# Realtime Save and TAS Replay Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development (recommended) or executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an opt-in realtime save setting that resumes the player at the exact quit spot, and add `Ctrl+R` / `Ctrl+P` / `Ctrl+S` replay controls to the existing debug-overlay TAS.

**Architecture:** Extend `SaveSnapshot` with optional resume transform data and let `WorldRuntime.setup_session()` stage the saved room around it. A game-layer `RealtimeSaveService` under `WorldRoot` captures the player every two seconds and on quit. `TasTool` gains the new shortcuts while keeping the existing `F5`-`F12` keys; `TasInputSource` is reused unchanged.

**Tech Stack:** Godot 4.7 / GDScript / existing `SaveManager`, `WorldSession`, `WorldRuntime`, `TasTool`, `TasInputSource`, `tests/run_test_script.gd` and `tests/run_runtime_suite.gd`.

---

## File Structure

- Modify `addons/platformer_kit/save/save_snapshot.gd`: optional resume transform serialization.
- Modify `addons/platformer_kit/save/save_manager.gd`: resume convenience API.
- Create `scripts/save/realtime_save_service.gd`: game-layer capture/flush service.
- Modify `scenes/runtime/world_root.tscn`: instantiate the service.
- Modify `scripts/app/main.gd` or `scripts/ui/main_menu.gd`: clear resume data when the setting is off.
- Modify `scripts/save/settings_catalog.gd`, `global_settings_manager.gd`: new toggle and getter/setter.
- Modify `addons/platformer_kit/world/runtime/world_runtime.gd`: resume staging and restore.
- Modify `scripts/player/player_controller.gd`: `resume_at()` that preserves the checkpoint spawn.
- Modify `addons/platformer_debug/runtime/tas_tool.gd`: shortcuts, room guard, metadata save/load, panel text.
- Modify `localization/menu.csv` and regenerate `.translation` files.
- Modify `docs/controls.md`, `README.md`, `CHANGELOG.md`, `docs/project-structure.md`.
- Tests: `tests/save/test_save_codec.gd`, `tests/save/test_save_slots.gd`,
  `tests/save/test_realtime_save.gd`, `tests/world/test_world_runtime.gd`,
  `tests/platformer_debug/test_tas_tool_hotkeys.gd`,
  `tests/ui/test_settings_pages.gd`, `tests/runtime_suite.gd`.

---

### Task 1: Snapshot resume data and SaveManager API

**Files:**
- Modify: `addons/platformer_kit/save/save_snapshot.gd`
- Modify: `addons/platformer_kit/save/save_manager.gd`
- Modify: `tests/save/test_save_codec.gd`
- Modify: `tests/save/test_save_slots.gd`

- [ ] **Step 1: Write failing snapshot tests**

Add to `tests/save/test_save_codec.gd`:

```gdscript
	_assert_resume_state_round_trip(failures)
	_assert_invalid_resume_state_is_optional(failures)
```

and:

```gdscript
func _assert_resume_state_round_trip(failures: Array[String]) -> void:
	var snapshot: RefCounted = SAVE_SNAPSHOT.new()
	snapshot.slot = 1
	if not snapshot.has_method("set_resume_state"):
		failures.append("SaveSnapshot is missing set_resume_state")
		return
	if not snapshot.call("set_resume_state", Vector2(12, 34), Vector2(5, -6)):
		failures.append("SaveSnapshot rejected a finite resume transform")
	var decoded: RefCounted = SAVE_CODEC.new().decode(SAVE_CODEC.new().encode(snapshot), 1)
	if decoded == null:
		failures.append("resume state round trip lost the snapshot")
		return
	if not bool(decoded.get("has_resume")):
		failures.append("resume state flag did not round trip")
	if Vector2(decoded.get("resume_position")) != Vector2(12, 34):
		failures.append("resume position did not round trip")
	if Vector2(decoded.get("resume_velocity")) != Vector2(5, -6):
		failures.append("resume velocity did not round trip")
	decoded.call("clear_resume_state")
	if bool(decoded.get("has_resume")) or not (decoded.to_dictionary().get("player_resume", {}) as Dictionary).is_empty():
		failures.append("clear_resume_state left data behind")


func _assert_invalid_resume_state_is_optional(failures: Array[String]) -> void:
	var snapshot: RefCounted = SAVE_SNAPSHOT.new()
	snapshot.slot = 1
	snapshot.world_id = "kept_world"
	var data: Dictionary = snapshot.to_dictionary()
	data["player_resume"] = {"position": {"x": "bad", "y": 0}, "velocity": {"x": 0, "y": 0}}
	var decoded: RefCounted = SAVE_CODEC.new().decode(JSON.stringify(data), 1)
	if decoded == null:
		failures.append("malformed optional resume data rejected the whole save")
	elif decoded.world_id != "kept_world" or bool(decoded.get("has_resume")):
		failures.append("malformed optional resume data was not ignored")
```

- [ ] **Step 2: Run the focused test and watch RED**

```powershell
& 'D:\Godot4\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' --headless --path . -s res://tests/run_test_script.gd -- res://tests/save/test_save_codec.gd
```

Expected: failures mention `set_resume_state` / missing resume fields.

- [ ] **Step 3: Implement snapshot and manager**

In `SaveSnapshot` add:

```gdscript
var has_resume := false
var resume_position := Vector2.ZERO
var resume_velocity := Vector2.ZERO


func set_resume_state(position: Vector2, velocity: Vector2) -> bool:
	if not position.is_finite() or not velocity.is_finite():
		return false
	resume_position = position
	resume_velocity = velocity
	has_resume = true
	return true


func clear_resume_state() -> void:
	has_resume = false
	resume_position = Vector2.ZERO
	resume_velocity = Vector2.ZERO
```

Add `"player_resume": _serialize_resume()` to `to_dictionary()`, where
`_serialize_resume()` returns `{}` when `has_resume` is false, otherwise the
position/velocity object. In `load_from_dictionary()`, parse
`data.get("player_resume", {})` only when it is a Dictionary; ignore malformed
values rather than returning `null`.

In `PlatformerSaveManager` add:

```gdscript
func set_resume_state(position: Vector2, velocity: Vector2, immediate := false) -> bool:
	if current_snapshot == null:
		return false
	if not current_snapshot.set_resume_state(position, velocity):
		return false
	if immediate:
		return commit()
	queue_commit()
	return true


func clear_resume_state(immediate := false) -> bool:
	if current_snapshot == null:
		return false
	current_snapshot.clear_resume_state()
	if immediate:
		return commit()
	queue_commit()
	return true
```

- [ ] **Step 4: Add manager tests**

In `tests/save/test_save_slots.gd` add a test that creates a manager with a
recording storage, assigns `current_snapshot`, calls
`set_resume_state(Vector2(4, 8), Vector2(1, 0), true)`, asserts the snapshot
has the resume values, then calls `clear_resume_state(true)` and asserts it is
cleared. Also assert both calls return `false` when `current_snapshot` is null.

- [ ] **Step 5: Run focused tests and watch GREEN**

Run the two focused tests. Expected: exit `0`, no failures.

- [ ] **Step 6: Commit**

```powershell
git add addons/platformer_kit/save/save_snapshot.gd addons/platformer_kit/save/save_manager.gd tests/save/test_save_codec.gd tests/save/test_save_slots.gd
git commit -m "feat: store player resume transform in save snapshots"
```

---

### Task 2: Realtime setting and capture service

**Files:**
- Modify: `scripts/save/settings_catalog.gd`
- Modify: `scripts/save/global_settings_manager.gd`
- Create: `scripts/save/realtime_save_service.gd`
- Modify: `scenes/runtime/world_root.tscn`
- Modify: `scripts/ui/main_menu.gd`
- Test: `tests/save/test_realtime_save.gd`
- Test: `tests/ui/test_settings_pages.gd`
- Modify: `tests/runtime_suite.gd`

- [ ] **Step 1: Write failing setting and service tests**

In `tests/ui/test_settings_pages.gd` add `&"realtime_save_enabled"` to the
expected-key list and assert:

```gdscript
	var realtime: SettingsDefinition = CATALOG.find_definition(&"realtime_save_enabled")
	if realtime == null:
		failures.append("settings catalog is missing realtime_save_enabled")
	elif realtime.section != CATALOG.GAME or realtime.kind != DEFINITION.KIND_TOGGLE:
		failures.append("realtime save must be a Game toggle")
	elif bool(realtime.default_value):
		failures.append("realtime save must default to off")
```

Create `tests/save/test_realtime_save.gd` with a fake player, fake settings,
and fake manager. It must assert:

- `bind_sources()` + `set_active(true)` + `capture_now()` captures position and
  velocity into the manager.
- A second `capture_now()` without movement does not write again.
- Setting `enabled = false` and emitting `settings_changed` clears resume data.
- `capture_now()` while disabled returns `false`.
- `flush()` performs an immediate commit.

- [ ] **Step 2: Run focused tests and watch RED**

Expected: setting key missing and service script missing.

- [ ] **Step 3: Implement setting + service**

Add the catalog toggle and getter/setter exactly as designed. Implement
`RealtimeSaveService` with:

```gdscript
class_name RealtimeSaveService
extends Node

@export var player_path := NodePath("../Player")
@export var session_path := NodePath("..")
@export var interval_seconds := 2.0
@export var save_manager_path := NodePath("/root/SaveManager")
@export var settings_path := NodePath("/root/GlobalSettings")

var _player: Node
var _session: Node
var _save_manager: Node
var _settings: Node
var _active := false
var _enabled := false
var _elapsed := 0.0
var _last_position := Vector2.INF
var _last_velocity := Vector2.INF
```

Public methods: `bind_sources(player, save_manager, settings, session = null)`,
`set_active(value)`, `capture_now(immediate := false) -> bool`,
`flush() -> bool`. On `_ready()`, resolve paths, connect
`settings_changed`, `world_ready`, and `world_start_failed`, then apply the
setting. `_process(delta)` accumulates and calls `capture_now()` every
`interval_seconds`. `_notification(NOTIFICATION_WM_CLOSE_REQUEST)` and
`_exit_tree()` call `flush()`.

`capture_now()` reads `player.global_position` and the `velocity` property when
present, false when disabled/inactive/missing snapshot, skips identical
transforms, and calls
`save_manager.set_resume_state(position, velocity, immediate)`.

- [ ] **Step 4: Wire the service and menu guard**

Add a `RealtimeSave` node with the new script as a child of `WorldRoot` in
`scenes/runtime/world_root.tscn`. In `MainMenu._start_game()`, after
`prepare_slot()`, when `/root/GlobalSettings` exists and
`is_realtime_save_enabled()` is false, call `snapshot.clear_resume_state()`.

- [ ] **Step 5: Run focused tests and watch GREEN**

Run `test_settings_pages.gd` and `test_realtime_save.gd`. Expected: exit `0`.

- [ ] **Step 6: Commit**

```powershell
git add scripts/save/settings_catalog.gd scripts/save/global_settings_manager.gd scripts/save/realtime_save_service.gd scenes/runtime/world_root.tscn scripts/ui/main_menu.gd tests/save/test_realtime_save.gd tests/ui/test_settings_pages.gd tests/runtime_suite.gd
git commit -m "feat: add realtime save setting and capture service"
```

---

### Task 3: Restore the live transform

**Files:**
- Modify: `addons/platformer_kit/world/runtime/world_runtime.gd`
- Modify: `scripts/player/player_controller.gd`
- Modify: `tests/world/test_world_runtime.gd`

- [ ] **Step 1: Write the failing restore test**

In `tests/world/test_world_runtime.gd`, extend `TestPlayer` with
`velocity`, `spawn_position`, and `resume_at(position, velocity, checkpoint)`.
Add a fixture test:

```gdscript
	var snapshot: RefCounted = SAVE_SNAPSHOT.new()
	snapshot.world_id = world.world_id
	snapshot.current_room_id = "room_a"
	snapshot.respawn_room_id = "room_a"
	snapshot.respawn_spawn_id = "entry"
	snapshot.respawn_position = Vector2(8, 12)
	snapshot.set_resume_state(Vector2(100, 50), Vector2(30, -40))
```

Start `WORLD_RUNTIME` with this snapshot and a `TestPlayer`, then assert the
player is at `(100, 50)`, velocity is `(30, -40)`, and
`spawn_position` remains `(8, 12)`. Add a second case where the resume position
is outside every room and assert the player lands at the normal spawn.

- [ ] **Step 2: Run the focused test and watch RED**

Expected: player lands at `(8, 12)` instead of `(100, 50)`.

- [ ] **Step 3: Implement restore**

In `WorldRuntime.setup_session()` resolve the resume record before staging:

```gdscript
func _resolve_resume(data: Resource, snapshot: RefCounted) -> Dictionary:
	if snapshot == null or not bool(snapshot.get("has_resume")):
		return {}
	if snapshot.world_id != data.world_id:
		return {}
	var target: Vector2 = Vector2(snapshot.get("resume_position"))
	var speed: Vector2 = Vector2(snapshot.get("resume_velocity"))
	if not target.is_finite() or not speed.is_finite():
		return {}
	var local_position := to_local(target)
	var room_id: String = data.get_room_id_at_world_position(local_position, snapshot.current_room_id)
	if room_id.is_empty():
		return {}
	return {
		"position": target,
		"velocity": speed,
		"room_id": room_id,
		"chunk": data.get_chunk_at_world_position(local_position),
	}
```

Use the resume room/chunk for `_stage_world()`, align resident rooms around
the resume chunk, and skip the spawn alignment path. After `_commit_world()`,
call `_restore_player_resume()` instead of `_respawn_player(spawn.global_position)`.
Keep `_initialize_snapshot()` unchanged so the checkpoint respawn identity is
preserved.

Add to `PlayerController`:

```gdscript
func resume_at(pos: Vector2, restored_velocity: Vector2, checkpoint_position := Vector2.INF) -> void:
	respawn_at(pos)
	if checkpoint_position.is_finite():
		spawn_position = checkpoint_position
	velocity = restored_velocity if restored_velocity.is_finite() else Vector2.ZERO
	_world_velocity = velocity
```

- [ ] **Step 4: Run focused tests and watch GREEN**

Run `test_world_runtime.gd` and `test_killzone.gd`. Expected: exit `0`.

- [ ] **Step 5: Commit**

```powershell
git add addons/platformer_kit/world/runtime/world_runtime.gd scripts/player/player_controller.gd tests/world/test_world_runtime.gd
git commit -m "feat: restore player resume transform on world start"
```

---

### Task 4: TAS shortcuts and replay guard

**Files:**
- Modify: `addons/platformer_debug/runtime/tas_tool.gd`
- Create: `tests/platformer_debug/test_tas_tool_hotkeys.gd`
- Modify: `tests/runtime_suite.gd`

- [ ] **Step 1: Write the failing hotkey test**

Create a test with a `FakePlayer` exposing `set_input_source()` /
`get_input_source()` / `respawn_at()`. Instantiate `tas_tool.tscn`, set
`recording_path` to `user://tas_hotkey_test.json`, add the player as a sibling,
then call `_unhandled_input()` with synthetic key events:

- `Ctrl+R` starts recording, a frame is recorded through the player's source,
  `Ctrl+R` stops it.
- `Ctrl+S` writes the fixed file.
- `Ctrl+P` starts playback, `Ctrl+P` again stops it.
- `F6` still starts recording.

Delete the test file at the end.

- [ ] **Step 2: Run focused test and watch RED**

Expected: `Ctrl+R` does nothing because only `F6` is handled.

- [ ] **Step 3: Implement shortcuts and metadata**

Rework `_unhandled_input()`:

```gdscript
		KEY_R:
			if key_event.ctrl_pressed:
				_toggle_record()
		KEY_P:
			if key_event.ctrl_pressed:
				_toggle_playback()
		KEY_S:
			if key_event.ctrl_pressed:
				_save()
```

Keep `F5`-`F12`. Add `_toggle_playback()` that stops an active playback instead
of restarting it. Add world/room tracking by walking up to the `WorldSession`
and resolving its `WorldRuntime`. On record start, capture
`_start_position`, `_start_world_id`, and `_start_room_id` from the current
position (do not teleport to the previous start). On play, refuse when the
current room/world differs. `_save()` stops recording first, writes
`version`, `physics_ticks`, `start`, `world_id`, `room_id`, and `frames` to
`user://tas_recording.json` through a temp file plus rename, and reports
`saved N frames`. `_load()` restores the optional world/room metadata. Update
the panel text to show `Ctrl+R rec`, `Ctrl+P play`, `Ctrl+S save`.

- [ ] **Step 4: Run focused tests and watch GREEN**

Run `test_tas_input_source.gd` and `test_tas_tool_hotkeys.gd`. Expected: exit
`0`, no leftover test recording.

- [ ] **Step 5: Commit**

```powershell
git add addons/platformer_debug/runtime/tas_tool.gd tests/platformer_debug/test_tas_tool_hotkeys.gd tests/runtime_suite.gd
git commit -m "feat: add Ctrl replay shortcuts to the debug TAS"
```

---

### Task 5: Localization, documentation, verification

**Files:**
- Modify: `localization/menu.csv`
- Regenerate: `localization/menu.en.translation`, `localization/menu.zh_CN.translation`
- Modify: `docs/controls.md`
- Modify: `README.md`
- Modify: `CHANGELOG.md`
- Modify: `docs/project-structure.md`

- [ ] **Step 1: Add translation rows**

Add:

```csv
SETTINGS_REALTIME_SAVE,Realtime Save,实时存档
SETTINGS_DESC_REALTIME_SAVE,"Resume at the exact spot where you left, even after quitting; death still returns to the last checkpoint.",退出后从离开时的精确位置继续；死亡仍回到最近的检查点。
```

Regenerate the `.translation` files with:

```powershell
& 'D:\Godot4\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --import
```

- [ ] **Step 2: Update docs**

`docs/controls.md`: list `Ctrl+R`, `Ctrl+P`, `Ctrl+S` and keep the `F` aliases.
`README.md`: mention realtime save and replay. `CHANGELOG.md`: add both features.
`docs/project-structure.md`: add `scripts/save/realtime_save_service.gd`.

- [ ] **Step 3: Run every focused test**

```powershell
& 'D:\Godot4\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' --headless --path . -s res://tests/run_test_script.gd -- res://tests/save/test_save_codec.gd
& 'D:\Godot4\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' --headless --path . -s res://tests/run_test_script.gd -- res://tests/save/test_save_slots.gd
& 'D:\Godot4\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' --headless --path . -s res://tests/run_test_script.gd -- res://tests/save/test_realtime_save.gd
& 'D:\Godot4\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' --headless --path . -s res://tests/run_test_script.gd -- res://tests/world/test_world_runtime.gd
& 'D:\Godot4\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' --headless --path . -s res://tests/run_test_script.gd -- res://tests/platformer_debug/test_tas_tool_hotkeys.gd
& 'D:\Godot4\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' --headless --path . -s res://tests/run_test_script.gd -- res://tests/ui/test_settings_pages.gd
```

Expected: every command exits `0`.

- [ ] **Step 4: Check every touched script**

```powershell
& 'D:\Godot4\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --check-only -s res://scripts/save/realtime_save_service.gd
& 'D:\Godot4\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --check-only -s res://addons/platformer_debug/runtime/tas_tool.gd
& 'D:\Godot4\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --check-only -s res://addons/platformer_kit/world/runtime/world_runtime.gd
& 'D:\Godot4\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --check-only -s res://scripts/player/player_controller.gd
```

Expected: exit `0`, no parser/analyzer warnings.

- [ ] **Step 5: Run the full suite and compare with baseline**

```powershell
& 'D:\Godot4\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' --headless --log-file '.godot/realtime_save_final_suite.log' --path . -s res://tests/run_runtime_suite.gd
```

The workspace baseline already exits nonzero (pre-existing dirty-worktree
failures). Record the baseline failure text first and confirm this run adds no
new failure that names the new files or behaviors.

- [ ] **Step 6: Commit**

```powershell
git add localization/menu.csv localization/menu.en.translation localization/menu.zh_CN.translation docs/controls.md README.md CHANGELOG.md docs/project-structure.md
git commit -m "docs: document realtime save and replay"
```

---

## Self-Review

- Spec coverage: settings, snapshot, service, restore, replay shortcuts,
  localization, docs, and tests each have a task.
- Placeholder scan: no TBD/TODO; each implementation step names files and
  APIs.
- Type consistency: `set_resume_state`, `clear_resume_state`, `resume_at`,
  `_toggle_playback`, and `RealtimeSaveService` keep the same names across
  tasks.
