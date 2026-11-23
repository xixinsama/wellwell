# World Editor Main Screen Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the narrow World Editor dock with a standard Godot main-screen workspace that explicitly manages `WorldData`, safely imports authored rooms, and provides complete chunk-grid navigation.

**Architecture:** `world_editor_plugin.gd` hosts a scene-backed `WorldEditorMain` in `EditorInterface.get_editor_main_screen()`. Pure authoring services own world-resource persistence, room import transactions, and canvas transform math; the scene controller coordinates those services and delegates world mutations to the existing `WorldLayoutModel`. `WorldLayoutCanvas` remains the visual/input surface and never mutates resources except through the controller's undoable commands.

**Tech Stack:** Godot 4.7.2, typed GDScript `@tool` scripts, `EditorPlugin`, `EditorResourcePicker`, `EditorUndoRedoManager`, `ResourceSaver`, `ResourceLoader`, and the repository's plain-GDScript runtime suite.

**Spec:** `docs/superpowers/specs/2026-09-06-world-editor-main-screen-redesign.md`

## Global Constraints

- Work directly on branch `level0`; do not create a worktree and do not commit.
- The implementation agent must not edit `scenes/levels/level_0.tscn`, `level_1.tscn`, `level_2.tscn`, `scenes/templates/level_template.tscn`, or authored tile data. User-owned scene corrections are external to implementation completion.
- Do not edit `docs/todo.md`.
- Preserve exact room placement units of `Vector2i(320, 180)` pixels per chunk.
- Use documented public Godot APIs only; do not inspect or modify internal `CanvasItemEditor` nodes.
- Keep visual Godot acceptance user-owned. Automated work may use headless editor initialization and scene-contract tests.
- Run Godot with `D:/Godot4/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe` because `godot` is not in `PATH`.
- Every production change follows RED, GREEN, REFACTOR; preserve unrelated dirty-worktree changes.

---

### Task 1: Replace The Dock With A Main-Screen Scene

**Files:**
- Create: `tests/authoring/test_world_editor_main_screen.gd`
- Modify: `tests/runtime_suite.gd`
- Rename: `addons/wellwell_world_editor/world_editor_dock.gd` to `addons/wellwell_world_editor/world_editor_main.gd`
- Rename: `addons/wellwell_world_editor/world_editor_dock.tscn` to `addons/wellwell_world_editor/world_editor_main.tscn`
- Modify: `addons/wellwell_world_editor/world_editor_main.gd`
- Modify: `addons/wellwell_world_editor/world_editor_main.tscn`
- Modify: `addons/wellwell_world_editor/world_editor_plugin.gd`
- Modify: `addons/wellwell_world_editor/world_layout_canvas.gd`
- Modify: `addons/wellwell_world_editor/plugin.cfg`
- Modify: `tests/authoring/test_world_editor_commands.gd`

**Interfaces:**
- Consumes: existing controller methods `set_world_data()`, `set_undo_redo_adapter()`, and `set_editor_interface()`.
- Produces: controller type `class_name WorldEditorMain`, `_has_main_screen() -> bool`, `_make_visible(visible: bool)`, `_get_plugin_name() -> String`, and `_get_plugin_icon() -> Texture2D`.

- [ ] **Step 1: Write the failing main-screen contract test**

Add the new test to `tests/runtime_suite.gd`, then assert real plugin behavior and scene structure:

```gdscript
extends Node

const PLUGIN := preload("res://addons/wellwell_world_editor/world_editor_plugin.gd")
const MAIN_SCENE_PATH := "res://addons/wellwell_world_editor/world_editor_main.tscn"

func run() -> Array[String]:
	var failures: Array[String] = []
	var plugin := PLUGIN.new()
	if not plugin.call("_has_main_screen"):
		failures.append("World Editor is not registered as a main-screen plugin")
	if plugin.call("_get_plugin_name") != "World":
		failures.append("World Editor main-screen name is not World")
	var packed := load(MAIN_SCENE_PATH) as PackedScene
	if packed == null:
		failures.append("World Editor main-screen scene is missing")
	else:
		var main := packed.instantiate() as Control
		if (main.size_flags_vertical & Control.SIZE_EXPAND) == 0:
			failures.append("World Editor main screen does not expand vertically")
		main.free()
	plugin.free()
	return failures
```

- [ ] **Step 2: Run the suite and verify RED**

Run:

```powershell
& 'D:/Godot4/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe' --headless --path . -s res://tests/run_runtime_suite.gd
```

Expected: FAIL because the main scene and main-screen virtual methods do not exist.

- [ ] **Step 3: Rename the dock scene/controller and implement documented plugin hosting**

Retain the existing command methods while changing the controller class and root sizing. Replace dock registration with:

```gdscript
@tool
extends EditorPlugin

const MAIN_SCENE := preload("res://addons/wellwell_world_editor/world_editor_main.tscn")
var _main: Control

func _enter_tree() -> void:
	_main = MAIN_SCENE.instantiate() as Control
	_main.set_undo_redo_adapter(get_undo_redo())
	_main.set_editor_interface(get_editor_interface())
	EditorInterface.get_editor_main_screen().add_child(_main)
	_make_visible(false)

func _exit_tree() -> void:
	if is_instance_valid(_main):
		_main.queue_free()
	_main = null

func _has_main_screen() -> bool:
	return true

func _make_visible(visible: bool) -> void:
	if is_instance_valid(_main):
		_main.visible = visible

func _get_plugin_name() -> String:
	return "World"

func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_editor_theme().get_icon("Node2D", "EditorIcons")
```

Keep `_handles(object)` and `_edit(object)` but route them to `_main`. Remove every `add_control_to_dock()` and `remove_control_from_docks()` call. Rename the canvas's `_dock` collaborator and `set_dock()` API to `_main` and `set_main_screen()`. Update command tests to load the renamed scene/controller, and update `plugin.cfg` to version `0.2.0` with a main-workspace description.

- [ ] **Step 4: Run focused and complete tests**

Run the full runtime-suite command. Expected: PASS with no missing-scene, placeholder, or main-screen contract errors.

- [ ] **Step 5: Initialize the enabled plugin in editor context**

Run:

```powershell
& 'D:/Godot4/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe' --headless --editor --path . --quit-after 5
```

Expected: exit 0 with no script/plugin errors. The scan-aborted warning caused by `--quit-after` is acceptable.

---

### Task 2: Add Explicit World Resource Creation, Loading, And Saving

**Files:**
- Create: `scripts/authoring/world_resource_service.gd`
- Create: `tests/authoring/test_world_resource_service.gd`
- Modify: `tests/runtime_suite.gd`
- Modify: `addons/wellwell_world_editor/world_editor_main.tscn`
- Modify: `addons/wellwell_world_editor/world_editor_main.gd`

**Interfaces:**
- Produces: `WorldResourceService.create_world(path: String) -> Dictionary`, `load_world(path: String) -> Dictionary`, `save_world(world: WorldData) -> Dictionary`, and `save_candidate(world: WorldData, final_path: String) -> Dictionary`.
- Produces scene nodes: `%WorldPicker`, `%NewWorld`, `%SaveWorld`, and `%NewWorldDialog`.

- [ ] **Step 1: Write failing resource-service tests**

Cover valid creation, filename-derived `world_id`, non-`res://` rejection, rejection outside `res://resources/worlds/`, wrong-extension rejection, load type checking, save of an existing world, and forced save failure. Use a test-only filename under `res://resources/worlds/` and always remove `.tres`, `.stage.tres`, and `.backup.tres` outputs.

```gdscript
var result := service.create_world("res://resources/worlds/test_main_world.tres")
if not result.get("ok", false):
	failures.append("valid WorldData creation failed")
elif result["world"].world_id != "test_main_world":
	failures.append("world_id was not derived from the filename")
	if service.create_world("user://bad.tres").get("ok", true):
		failures.append("world creation accepted a non-res path")
	if service.create_world("res://tests/bad_world.tres").get("ok", true):
		failures.append("world creation accepted a path outside resources/worlds")
```

- [ ] **Step 2: Run the suite and verify RED**

Expected: FAIL because `world_resource_service.gd` is missing.

- [ ] **Step 3: Implement transactional world-resource persistence**

Create an `@tool RefCounted` service. `save_candidate()` must save to a marked stage path, reload with `ResourceLoader.CACHE_MODE_IGNORE`, verify script type and a deterministic world signature, back up an existing final, promote the stage, and restore the backup on failure. Return the common envelope:

```gdscript
{
	"ok": errors.is_empty(),
	"errors": errors,
	"warnings": warnings,
	"world": loaded_world,
	"path": final_path,
}
```

`create_world()` derives the ID with `path.get_file().get_basename()`, rejects an existing file, and delegates to `save_candidate()`. `save_world()` rejects null or unsaved resources.

- [ ] **Step 4: Add the resource picker and world commands to the scene**

Use an `EditorResourcePicker` restricted to `WorldData`, plus icon buttons and a resource-mode save `FileDialog`. Set both `current_dir` and `root_subfolder` to `res://resources/worlds/` so the dialog opens in and remains confined to the world-resource directory. Controller behavior:

```gdscript
func _on_world_resource_changed(resource: Resource) -> void:
	set_world_data(resource as WorldData)

func _on_new_world_path_selected(path: String) -> void:
	var result := _world_resources.create_world(path)
	if result.get("ok", false):
		set_world_data(result["world"])
	_show_result(result)
```

Define `set_world_data(value: WorldData, preserve_selection := false)`. It updates `%WorldPicker.edited_resource`; it retains `selected_room_id` only when `preserve_selection` is true and the new world still contains that ID, otherwise it clears selection. It then refreshes the canvas and command states. `_edit(WorldData)` calls this single entry point with `preserve_selection = true`.

- [ ] **Step 5: Extend scene/controller tests and run GREEN**

Assert required nodes, picker base type, dialog resource access/filter, `current_dir`, `root_subfolder`, explicit status on null-world save, selection clear/preserve behavior, and that selecting a resource updates `world_data`. Run the complete runtime suite and verify PASS.

---

### Task 3: Introduce Testable Canvas Transform Math

**Files:**
- Create: `scripts/authoring/world_canvas_view.gd`
- Create: `tests/authoring/test_world_canvas_view.gd`
- Modify: `tests/runtime_suite.gd`
- Modify: `addons/wellwell_world_editor/world_layout_canvas.gd`

**Interfaces:**
- Produces: `WorldCanvasView.world_to_screen(world_pixels: Vector2, viewport_size: Vector2) -> Vector2`.
- Produces: `screen_to_world(screen_position: Vector2, viewport_size: Vector2) -> Vector2`.
- Produces: `zoom_at(screen_position: Vector2, factor: float, viewport_size: Vector2) -> void`.
- Produces: `pan_screen_delta(delta: Vector2) -> void`, `fit_world_rect(rect: Rect2, viewport_size: Vector2, padding: float = 48.0) -> void`, and `reset() -> void`.

- [ ] **Step 1: Write failing transform tests**

Test round trips, zoom clamping, cursor anchoring, pan direction, one-room focus, multi-room focus, empty focus, and reset:

```gdscript
var before := view.screen_to_world(cursor, viewport_size)
view.zoom_at(cursor, 1.2, viewport_size)
var after := view.screen_to_world(cursor, viewport_size)
if not before.is_equal_approx(after):
	failures.append("cursor-anchored zoom moved the world point")
```

- [ ] **Step 2: Run the suite and verify RED**

Expected: FAIL because `WorldCanvasView` is missing.

- [ ] **Step 3: Implement the pure view model**

Use these invariants:

```gdscript
const MIN_ZOOM := 0.1
const MAX_ZOOM := 4.0
var view_center_world_pixels := Vector2.ZERO
var zoom := 1.0

func world_to_screen(world_pixels: Vector2, viewport_size: Vector2) -> Vector2:
	return (world_pixels - view_center_world_pixels) * zoom + viewport_size * 0.5

func screen_to_world(screen_position: Vector2, viewport_size: Vector2) -> Vector2:
	return (screen_position - viewport_size * 0.5) / zoom + view_center_world_pixels
```

For cursor zoom, capture the world point before changing zoom and shift `view_center_world_pixels` so the same point maps back to the cursor. `fit_world_rect()` uses the smaller available-axis scale and clamps it.

- [ ] **Step 4: Route canvas rectangle and connection geometry through the view model**

Replace fixed `VIEW_SCALE` and `_canvas_origin()` calculations. Keep `RoomData.room_origin_chunk` and `room_size_chunks` unchanged; convert them to world pixels before applying the view transform.

- [ ] **Step 5: Run focused and complete tests**

Expected: all transform and existing overlap/connection tests PASS.

---

### Task 4: Implement Canvas Navigation, Grid, Guides, And Coordinates

**Files:**
- Modify: `addons/wellwell_world_editor/world_layout_canvas.gd`
- Modify: `addons/wellwell_world_editor/world_editor_main.tscn`
- Modify: `addons/wellwell_world_editor/world_editor_main.gd`
- Modify: `tests/authoring/test_world_editor_commands.gd`
- Modify: `tests/authoring/test_world_canvas_view.gd`

**Interfaces:**
- Produces canvas commands `focus_all() -> void`, `focus_room(room_id: String) -> bool`, and `reset_view() -> void`.
- Produces gesture methods `begin_room_drag(room_id: String, screen_position: Vector2) -> bool`, `update_room_drag(screen_position: Vector2) -> void`, and `update_cursor(screen_position: Vector2) -> void`; `_gui_input()` delegates to them.
- Produces query helpers `get_cursor_world_pixels() -> Vector2`, `get_cursor_chunk() -> Vector2i`, `get_visible_grid_lines() -> Dictionary`, and `get_drag_preview_chunk() -> Vector2i` for deterministic tests.
- Produces scene nodes `%FocusAll`, `%ResetView`, and `%ZoomLabel`.

- [ ] **Step 1: Add failing navigation and grid tests**

Cover wheel zoom direction, middle-drag pan, Space+left pan state, room drag precedence, exact non-square chunk snapping, visible grid spacing, zero-axis inclusion, focus-all bounds, and drag preview guides.

```gdscript
canvas.size = Vector2(1000, 700)
canvas.call("begin_room_drag", "room_a", Vector2(500, 350))
canvas.call("update_room_drag", Vector2(500 + 320, 350 + 180))
if canvas.call("get_drag_preview_chunk") != Vector2i(1, 1):
	failures.append("room drag did not snap by one complete 320x180 chunk")
```

- [ ] **Step 2: Run the suite and verify RED**

Expected: FAIL on missing navigation methods and controls.

- [ ] **Step 3: Implement input state without undocumented editor internals**

Handle `InputEventMouseButton`, `InputEventMouseMotion`, and `InputEventKey` inside `_gui_input()`:

- Wheel uses factors `1.2` and `1.0 / 1.2` around `event.position`.
- Middle drag pans immediately.
- Space records a temporary pan modifier; Space+left drag pans only when no room drag is active.
- Left drag on a room remains the placement gesture.
- Release always clears the matching gesture state.

Call `accept_event()` for consumed events and `queue_redraw()` after view changes.

- [ ] **Step 4: Draw the world grid and overlays**

Compute visible world bounds with `screen_to_world()`. Draw lines at integer multiples of 320 on X and 180 on Y, with stronger zero axes. Thin minor lines/labels when their screen spacing is below 32 pixels. Draw:

- visible chunk-coordinate labels,
- drag-origin cross guides and `(x, y)` text,
- cursor world/chunk coordinates,
- selected room origin/size,
- zoom percentage.

Use the editor theme colors where available and stable fallback colors otherwise. Keep room and connection drawing above the grid.

- [ ] **Step 5: Wire Focus All and Reset View controls**

Use icon buttons with tooltips. Focus All computes the union of every room's exact pixel rect; Reset View calls the view model's `reset()`. Refresh `%ZoomLabel` whenever zoom changes.

- [ ] **Step 6: Run the complete suite**

Expected: PASS with no layout changes to authored level scenes.

---

### Task 5: Make Add Existing A Four-File Transaction

**Files:**
- Create: `scripts/authoring/world_room_importer.gd`
- Create: `tests/authoring/test_world_room_importer.gd`
- Modify: `tests/runtime_suite.gd`
- Modify: `scripts/authoring/world_resource_service.gd`
- Modify: `scripts/authoring/room_authoring_contract.gd`
- Modify: `tests/authoring/test_room_authoring_contract.gd`

**Interfaces:**
- Consumes: `RoomBaker.stage()`, `RoomBaker.save_staged()`, `WorldLayoutModel.add_room()`, and `WorldResourceService.save_candidate()`.
- Produces: `WorldRoomImporter.import_room(world: WorldData, source_root: Node, source_path: String) -> Dictionary`.
- Produces injectable adapters: `set_room_baker_adapter(value: Object)`, `set_world_resources_adapter(value: Object)`, and `set_layout_model_adapter(value: Object)`.

- [ ] **Step 1: Add a failing preview-spawn contract test**

Construct an authoring root whose `preview_spawn_id` is `preview_a` while its only `SpawnPoint.spawn_id` is `start`. Expect validation to include:

```text
preview_spawn_id does not reference a SpawnPoint: preview_a
```

This improves diagnostics without editing the user's level scenes.

- [ ] **Step 2: Run the suite and verify preview validation RED**

Expected: FAIL only because preview-spawn mismatch is accepted.

- [ ] **Step 3: Implement preview-spawn validation**

Collect spawn IDs from `RoomContent` once, preserve duplicate-ID validation, then verify the root's non-empty `preview_spawn_id` exists in that set. Return the error through the existing contract envelope.

- [ ] **Step 4: Run the complete suite and verify preview validation GREEN**

Run the normal runtime-suite command before adding the importer test to `tests/runtime_suite.gd`. Expected: PASS, proving the contract change independently.

- [ ] **Step 5: Write failing import transaction tests**

Create `test_world_room_importer.gd`, register it in `tests/runtime_suite.gd`, and test null world, unsaved world, invalid source, duplicate ID before writes, successful import, first-room start endpoint assignment, non-empty missing-start rejection, generated final paths, final world reference path, forced room-save failure, forced world-save failure, rollback over existing orphan artifacts, and cleanup of outer backup files. Use a preview spawn that is not lexicographically first to prove the manifest value is authoritative.

```gdscript
var before := _read_all_final_bytes(paths, world.resource_path)
world_store.fail_next_save = true
var result := importer.import_room(world, source, SOURCE_PATH)
if result.get("ok", true):
	failures.append("import succeeded after forced world save failure")
if _read_all_final_bytes(paths, world.resource_path) != before:
	failures.append("failed import did not restore all room and world files")
```

- [ ] **Step 6: Run the suite and verify importer RED**

Expected: FAIL because `WorldRoomImporter` and its import transaction do not exist.

- [ ] **Step 7: Implement the importer and outer rollback boundary**

The importer must:

1. Reject null/unsaved worlds and invalid source paths.
2. Stage the room without writes.
3. Reject duplicate room IDs using a duplicated world.
4. If the candidate is the world's first room, assign `start_room_id` from the room ID and `start_spawn_id` from the validated manifest `preview_spawn_id`; reject a non-empty world whose start endpoint is missing.
5. Copy each existing room/world final to a distinct `.import_backup` file and separately record finals that did not exist.
6. Call `RoomBaker.save_staged()`.
7. Load the final `RoomData` with `CACHE_MODE_IGNORE`.
8. Build a fresh world candidate referencing that final resource.
9. Call `WorldResourceService.save_candidate()`.
10. Remove outer backups only after all results validate.
11. Restore prior files or delete newly created finals on any failure.

Return the saved world, imported room, source path, all four output paths, `before_state`, and `after_state`. Capture the two states with `WorldLayoutModel.capture_world_state()` so they include room membership, connections, adjacency, `start_room_id`, and `start_spawn_id`. Cleanup failures are warnings after a successful commit and errors during rollback. Tests remove intentionally retained warning evidence; a normal final verification run must leave no backup files.

- [ ] **Step 8: Run importer tests and the complete suite**

Expected: PASS, with no `.stage`, `.backup`, or `.import_backup` files left under generated/resource directories.

---

### Task 6: Integrate Main-Screen Commands And Explicit Error States

**Files:**
- Modify: `addons/wellwell_world_editor/world_editor_main.gd`
- Modify: `addons/wellwell_world_editor/world_editor_main.tscn`
- Modify: `tests/authoring/test_world_editor_commands.gd`

**Interfaces:**
- Consumes: `WorldRoomImporter.import_room()` and `WorldResourceService.save_world()`.
- Produces: `set_world_room_importer_adapter(value: Object)`, `set_world_resource_service_adapter(value: Object)`, `_refresh_command_state()`, and `_show_result(result: Dictionary)` with persistent tooltip details.

- [ ] **Step 1: Write failing command-state and Add Existing tests**

Cover:

- Add Existing disabled with no active world and tooltip `Select or create a WorldData resource first`.
- Saved active world enables Add Existing.
- Unsaved world produces a visible error without opening the source dialog.
- Import failure displays the first error and full tooltip.
- Import success replaces the active world with the validated saved resource, selects/focuses the room, and reports output paths.
- `FakeUndo.commit_action(execute := true)` accepts the production signature, and successful import registers history without executing the do method twice.
- Import of a first room whose preview spawn is not the first sorted spawn sets the exact manifest preview spawn as the world start.
- Import undo restores the empty `before_state`, including clearing both start fields; redo restores the exact `after_state`, including the original manifest preview spawn.
- A forced undo/redo save failure does not replace the live validated world.
- New Room still opens `level_template.tscn` with `set_inherited = true`.
- Open Source uses the selected room's source path.

- [ ] **Step 2: Run the suite and verify RED**

Expected: FAIL because current commands still depend on implicit selection and direct baker calls.

- [ ] **Step 3: Replace direct Add Existing baking with the importer**

Keep the dialog callback small:

```gdscript
func _add_existing_source(path: String) -> void:
	if world_data == null or world_data.resource_path.is_empty():
		_show_result(_failure("Select or create a saved WorldData resource first"))
		return
	_set_transaction_busy(true)
	var source := _load_room_source(path)
	var result := _world_room_importer.import_room(world_data, source, path)
	if source != null:
		source.free()
	if result.get("ok", false):
		set_world_data(result["world"])
		select_room(result["room"].room_id)
		canvas.call("focus_room", selected_room_id)
	_set_transaction_busy(false)
	_show_result(result)
```

All early returns must show a result. Disable mutation buttons while `_transaction_busy` is true.

- [ ] **Step 4: Persist Add Existing undo and redo**

First update `FakeUndo.commit_action(execute := true)` and its assertions to model the real API. After a successful import, register history with `commit_action(false)` so the already-applied import is not repeated. Undo and redo each duplicate the live world, apply the importer's captured `before_state` or `after_state` through `WorldLayoutModel.restore_world_state()`, save that candidate, and replace the live world only after save succeeds. Neither path deletes generated room artifacts. Save failures leave the live validated world unchanged and appear in status.

- [ ] **Step 5: Improve status and resource-selection synchronization**

`_show_result()` joins all errors/warnings/output paths into `tooltip_text`, keeps the first message visible, and distinguishes success from failure. `_refresh_command_state()` owns all disabled flags and tooltips. `_edit(WorldData)` calls `set_world_data(value, true)` so only a still-valid selected room ID survives.

- [ ] **Step 6: Run complete automated verification**

Run the runtime suite and headless editor initialization. Expected: both exit 0 without placeholder, parse, signal, or plugin lifecycle errors.

---

### Task 7: Regression Audit And User-Owned Godot Acceptance

**Files:**
- Modify: `.superpowers/sdd/2026-09-05-level-authoring-world-editor/progress.md`
- Modify: `docs/superpowers/specs/2026-09-05-level-authoring-world-editor-design.md`
- Modify: `docs/superpowers/plans/2026-09-05-level-authoring-world-editor.md`

**Interfaces:**
- Consumes: all completed tasks and the accepted redesign spec.
- Produces: an explicit supersession note for the old dock design and a manual acceptance checklist.

- [ ] **Step 1: Mark old dock instructions as superseded**

Add a short note near the old editor sections linking to:

```text
docs/superpowers/specs/2026-09-06-world-editor-main-screen-redesign.md
docs/superpowers/plans/2026-09-06-world-editor-main-screen-redesign.md
```

Do not rewrite completed historical task records and do not modify `docs/todo.md`.

- [ ] **Step 2: Run all final automated checks**

Run:

```powershell
& 'D:/Godot4/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe' --headless --path . -s res://tests/run_runtime_suite.gd
& 'D:/Godot4/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe' --headless --editor --path . --quit-after 5
& 'D:/Godot4/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe' --headless --path . res://scenes/main.tscn --quit-after 5
git diff --check
```

Expected: all exit 0; only the known editor scan-aborted warning from forced quit and line-ending notices are acceptable.

- [ ] **Step 3: Verify repository invariants**

Confirm:

- no Godot process remains,
- no `.stage`, `.backup`, or `.import_backup` files remain after the normal verification run; explicitly reported cleanup-warning evidence must be removed before delivery,
- `docs/todo.md` is unchanged,
- no level/template scene is changed by this implementation,
- no `add_control_to_dock()` call remains in the plugin,
- every executable editor dependency remains `@tool`.

- [ ] **Step 4: Hand off the manual Godot checklist**

Ask the user to:

1. Restart Godot and confirm a top `World` workspace appears.
2. Create or select one saved world resource.
3. Add level 0 through **Add Existing** and confirm generated paths are reported. The known level 1/2 preview-ID mismatch is a separate user-owned prerequisite, not part of implementation completion.
4. After independently correcting those preview IDs, add level 1 and 2 and confirm the same workflow.
5. Confirm wheel zoom anchors at the pointer, middle/Space pan works, Focus All frames every room, Reset View returns to origin, and chunk coordinates/grid guides remain legible.
6. Drag rooms and confirm every committed origin is an integer 320x180 chunk.
7. Save/reopen the project and confirm all room references and connections persist.

Record any manual failure as a new Task 7 fix round before claiming completion.
