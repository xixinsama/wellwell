# Level Authoring And World Editor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver inherited room authoring, deterministic room/world baking, a minimal chunk-snapped world editor, and runtime integration without changing the existing authored tile placement.

**Architecture:** Authoring scenes own room-local content and manifests. `WorldData` owns placement and directed connections. Baking splits persistent terrain from streamed room content. A `WorldSession` binds one persistent player and presentation stack to `WorldRuntime`. The EditorPlugin delegates all mutations and validation to testable model/services.

**Tech Stack:** Godot 4.7, typed GDScript, `@tool`, `EditorPlugin`, `EditorUndoRedoManager`, `PackedScene`, `ResourceSaver`, `TileMapLayer`, headless runtime tests.

**Spec:** `docs/superpowers/specs/2026-09-05-level-authoring-world-editor-design.md`

## Global Constraints

- Work directly on branch `level0`; do not create a worktree.
- Do not modify `docs/todo.md` or tile placement in `scenes/game.tscn`.
- Preserve unrelated uncommitted runtime changes already present in the worktree.
- Use 320x180 pixel chunks and existing 8x8 tile semantics.
- Do not merge terrain into a global cell grid; position per-room terrain scenes at exact pixel origins.
- Add a failing test before each production behavior change.
- Ask the user to perform Godot-editor scene migration and visual checks at the marked checkpoints.
- Do not commit unless the user explicitly requests it.

---

### Task 1: Authoring Metadata And Scene Contract

**Files:**
- Create: `scripts/authoring/room_authoring_root.gd`
- Create: `scripts/authoring/room_authoring_contract.gd`
- Create: `tests/authoring/test_room_authoring_contract.gd`
- Modify: `tests/runtime_suite.gd`

- [ ] Write failing tests for required root/child names, six terrain layers, positive room size, unique entrance/spawn/entity IDs, and metadata extraction.
- [ ] Implement `@tool class_name RoomAuthoringRoot extends Node2D` with typed exports:

```gdscript
@export var room_id := ""
@export var display_name := ""
@export var room_size_chunks := Vector2i.ONE
@export var preview_spawn_id := "default"
@export var map_color := Color.WHITE
@export var tags := PackedStringArray()

func get_room_content() -> Node:
func get_preview_root() -> Node:
func get_manifest() -> Dictionary:
```

- [ ] Implement pure contract checks returning `Array[String]` errors and warnings separately.
- [ ] Ensure contract traversal accepts subclasses of `SpawnPoint`, `RoomEntrance`, and `WorldEntity`, not script-path equality.
- [ ] Register the new test in `tests/runtime_suite.gd` and run the headless suite.

**Verification:**

```powershell
godot --headless --path . -s res://tests/run_runtime_suite.gd
```

### Task 2: RoomData Provenance And Deterministic Bake Model

**Files:**
- Modify: `scripts/world/room_data.gd`
- Create: `scripts/authoring/room_bake_manifest.gd`
- Create: `scripts/authoring/room_bake_paths.gd`
- Create: `tests/authoring/test_room_bake_model.gd`
- Modify: `tests/world/test_world_data.gd`
- Modify: `tests/runtime_suite.gd`

- [ ] Write failing tests for deterministic generated paths, source/runtime/terrain path separation, and legacy `scene_path` compatibility.
- [ ] Add these `RoomData` exports without changing origin ownership:

```gdscript
@export_file("*.tscn") var source_scene_path := ""
@export_file("*.tscn") var terrain_scene_path := ""
```

- [ ] Implement `RoomBakePaths.for_room_id(room_id: String) -> Dictionary` using sanitized snake-case IDs and fixed generated directories.
- [ ] Implement a manifest containing room metadata plus sorted entrance, spawn, and entity ID arrays.
- [ ] Reject empty IDs and path collisions before touching output files.
- [ ] Run focused and complete headless tests.

### Task 3: Transactional Room Baker

**Files:**
- Create: `scripts/authoring/room_baker.gd`
- Create: `tests/authoring/test_room_baker.gd`
- Create directories: `scenes/rooms/generated/`, `resources/rooms/generated/`
- Modify: `tests/runtime_suite.gd`

- [ ] Create a synthetic authoring scene fixture in the test and first assert that baking excludes `PreviewOnly` and separates terrain.
- [ ] Implement `@tool class_name RoomBaker extends RefCounted`:

```gdscript
func validate(source_root: Node) -> Dictionary:
func stage(source_root: Node, source_path: String) -> Dictionary:
func save_staged(staged: Dictionary) -> Dictionary:
func bake(source_root: Node, source_path: String) -> Dictionary:
```

- [ ] Duplicate only owned authoring nodes. The terrain output contains `Background` and `Terrain`; runtime output contains `Entities`, `Foreground`, and other non-preview creator children.
- [ ] Preserve owner chains so `PackedScene.pack()` serializes all intended descendants.
- [ ] Save to temporary sibling paths, reload and validate all three artifacts, then atomically replace prior generated outputs.
- [ ] Return `{ok, errors, warnings, outputs}` and leave the last valid files untouched on failure.
- [ ] Test repeated bake determinism and a simulated validation failure.

### Task 4: Template Preview Controller

**Files:**
- Create: `scripts/authoring/room_preview_controller.gd`
- Create: `tests/authoring/test_room_preview_controller.gd`
- Modify: `scripts/world/room_entrance.gd`
- Modify: `tests/world/test_world_entity.gd`
- Modify: `tests/runtime_suite.gd`

- [ ] Write failing tests proving preview resolves `preview_spawn_id`, disables cross-room transitions, and does not call `SaveManager`.
- [ ] Remove destination ownership from author scenes by deprecating `RoomEntrance.target_room_id` and `target_spawn_id`; retain read compatibility for one migration phase but ignore them during resolution.
- [ ] Implement preview setup to bind the local player/camera/fog/HUD and place the player at the selected spawn.
- [ ] Keep save points visually usable but route persistence to an in-memory preview snapshot.
- [ ] Test a direct-preview scene tree entirely headlessly.

### Task 5: Manual Template Scene And Level Migration Checkpoint

**User-owned Godot editor work:**
- Create `scenes/templates/level_template.tscn` with the exact contract from the design spec.
- Create inherited `scenes/levels/level_0.tscn`.
- Move the existing authored tile layers and room-local creator content from `scenes/game.tscn` into `RoomContent` without changing tile coordinates or transforms.
- Configure `room_id`, room size, preview spawn, and preview bindings.
- Confirm direct room play, camera framing, fog bounds, and tile alignment visually.

**Agent follow-up:**
- [ ] Inspect only scene structure and serialized transforms; do not rewrite tile data.
- [ ] Add `tests/authoring/test_level_template_contract.gd` against the user-created scenes.
- [ ] Run the room contract and full runtime suite.
- [ ] Stop and report exact contract errors if the editor-authored scene is incomplete; do not auto-rearrange it.

### Task 6: World Layout Model And Validation

**Files:**
- Create: `scripts/authoring/world_layout_model.gd`
- Modify: `scripts/world/world_data.gd`
- Modify: `scripts/world/world_validation.gd`
- Create: `tests/authoring/test_world_layout_model.gd`
- Modify: `tests/world/test_world_validation.gd`
- Modify: `tests/runtime_suite.gd`

- [ ] Write failing tests for add/remove/move, integer chunk snapping, duplicate IDs, overlap warnings, start-room validity, unreachable rooms, and connection endpoint validation.
- [ ] Implement model methods that do not depend on editor UI:

```gdscript
func add_room(world: WorldData, room: RoomData) -> Dictionary:
func remove_room(world: WorldData, room_id: String) -> Dictionary:
func move_room(world: WorldData, room_id: String, origin_chunk: Vector2i) -> Dictionary:
func connect_rooms(world: WorldData, connection: RoomConnectionData) -> Dictionary:
func disconnect_rooms(world: WorldData, from_room_id: String, from_entrance_id: String) -> Dictionary:
func validate_world(world: WorldData) -> Dictionary:
```

- [ ] Removing a room deletes only membership and connections referring to it; it never deletes files.
- [ ] Allow overlap but return room-pair warnings.
- [ ] Load each room manifest to validate entrance/spawn endpoints without instantiating gameplay.
- [ ] Sort validation output and serialized arrays for deterministic diffs.

### Task 7: World Baker And Persistent Terrain Runtime

**Files:**
- Create: `scripts/authoring/world_baker.gd`
- Create: `scripts/world/world_terrain_runtime.gd`
- Modify: `scripts/world/room_runtime.gd`
- Modify: `scripts/world/world_runtime.gd`
- Create: `tests/authoring/test_world_baker.gd`
- Create: `tests/world/test_world_terrain_runtime.gd`
- Modify: `tests/world/test_room_runtime.gd`
- Modify: `tests/runtime_suite.gd`

- [ ] Write failing tests proving all terrain scenes load once at exact `origin_chunk * Vector2i(320, 180)` positions while runtime room content remains independently streamable.
- [ ] Implement `WorldBaker.bake(world: WorldData) -> Dictionary` to validate every referenced room artifact and save the world resource only after all checks pass.
- [ ] Implement `WorldTerrainRuntime.setup_world(world: WorldData) -> bool`, `get_room_terrain(room_id: String) -> Node`, and `clear_world() -> void`.
- [ ] Ensure `RoomRuntime` instantiates only `RoomData.scene_path`; terrain loading belongs exclusively to `WorldTerrainRuntime`.
- [ ] Add rollback tests for missing/corrupt terrain scenes.

### Task 8: Spatial Residency And Connection Authority

**Files:**
- Modify: `scripts/world/world_data.gd`
- Modify: `scripts/world/room_transition.gd`
- Modify: `scripts/world/world_runtime.gd`
- Modify: `scripts/world/room_entrance.gd`
- Modify: `tests/world/test_world_data.gd`
- Modify: `tests/world/test_room_transition.gd`
- Modify: `tests/world/test_world_runtime.gd`

- [ ] Write failing tests for rooms occupying the current/four-neighbor chunks, connected-room inclusion, duplicate-free residency, and source-entrance connection lookup.
- [ ] Add:

```gdscript
func get_room_ids_at_chunk(chunk: Vector2i) -> Array[String]:
func get_resident_room_ids(player_chunk: Vector2i, current_room_id: String) -> Array[String]:
func get_connection(from_room_id: String, from_entrance_id: String) -> RoomConnectionData:
```

- [ ] Resolve transitions only through `WorldData.get_connection()` and ignore legacy target fields on `RoomEntrance`.
- [ ] Stage all newly resident room content before unloading old content; preserve the previous set and player position if any stage fails.
- [ ] Recalculate residency only when the player's chunk or current room changes.
- [ ] Preserve current save restoration and entity-state behavior covered by existing dirty-worktree tests.

### Task 9: Dynamic Presentation Binding And Room-Local Fog

**Files:**
- Modify: `scripts/camera/pixel_camera_2d.gd`
- Modify: `scripts/tools/debug_hud.gd`
- Modify: `scripts/world/fog_of_war.gd`
- Create: `tests/world/test_runtime_bindings.gd`
- Modify: `tests/world/test_fog_visibility.gd`
- Modify: `tests/runtime_suite.gd`

- [ ] Write failing tests for runtime binding without NodePath dependencies and for rebinding fog on room changes.
- [ ] Add `bind_target(target: Node2D) -> void` to `PixelCamera2D` and `bind_player(player: Node) -> void` to `DebugHud`, while retaining exported NodePaths as scene defaults.
- [ ] Add to `FogOfWar`:

```gdscript
func bind_player(player: Node2D) -> void:
func bind_room(room_data: RoomData, terrain_root: Node) -> bool:
func clear_room() -> void:
```

- [ ] Resolve blockers from the active room's six layer names, set room bounds from chunk metadata, and update the `ImageTexture` every frame.
- [ ] Preserve flood-fill rules: solid/vision blockers stop expansion; glass is revealed but does not propagate beyond itself.

### Task 10: WorldSession Integration

**Files:**
- Create: `scripts/world/world_session.gd`
- Modify: `scenes/worlds/world_root.tscn`
- Modify: `scripts/main.gd`
- Modify: `scenes/main.tscn` only if non-tile composition changes are required
- Create: `tests/world/test_world_session.gd`
- Modify: `tests/ui/test_menu_features.gd`
- Modify: `tests/runtime_suite.gd`

- [ ] Write failing tests for saved/start spawn selection, persistent-player binding, readiness timing, and failure rollback.
- [ ] Implement `WorldSession.start(world, snapshot) -> bool` and a `world_ready` signal after terrain, required runtime rooms, and target spawn are ready.
- [ ] Keep one player, camera, fog, and HUD outside streamed room instances.
- [ ] Make menu flow hide gameplay UI only after `world_ready`; surface startup errors without discarding the selected save slot.
- [ ] Do not edit any tile cell data in `game.tscn`.

### Task 11: Minimal EditorPlugin Core

> **Superseded UI task:** The dock-specific steps below are historical. Use
> `docs/superpowers/specs/2026-09-06-world-editor-main-screen-redesign.md` and
> `docs/superpowers/plans/2026-09-06-world-editor-main-screen-redesign.md` for the active main-screen implementation.

**Files:**
- Create: `addons/wellwell_world_editor/plugin.cfg`
- Create: `addons/wellwell_world_editor/world_editor_plugin.gd`
- Create: `addons/wellwell_world_editor/world_editor_dock.gd`
- Create: `addons/wellwell_world_editor/world_editor_dock.tscn`
- Create: `addons/wellwell_world_editor/world_layout_canvas.gd`
- Create: `tests/authoring/test_world_editor_commands.gd`
- Modify: `tests/runtime_suite.gd`

- [ ] Test command creation against a fake undo/redo adapter before writing editor UI.
- [ ] Register a dock that activates for `WorldData` resources and delegates all changes to `WorldLayoutModel`.
- [ ] Implement only these commands: New Room, Add Existing, Remove Reference, Open Source, Connect, Disconnect, Validate Room, Bake Room, Validate World, Bake World.
- [ ] Draw room rectangles, name/ID, connection arrows, start-room marker, selected state, and overlap warnings.
- [ ] Convert drag deltas to integer chunk origins; never serialize pixel offsets.
- [ ] Use `EditorUndoRedoManager` for add/remove/move/connect/disconnect and mark the edited resource changed.
- [ ] Keep controls compact; no tile/entity editing or file deletion APIs may be present.

### Task 12: Manual Plugin And Gameplay Acceptance

**User-owned Godot editor work:**
- Enable `wellwell_world_editor` and confirm the dock opens without editor errors.
- Add `level_0`, drag it by multiple full chunks, undo/redo, and verify it cannot land between chunks.
- Create and remove a directed entrance-to-spawn connection.
- Confirm overlap warnings do not block saving or baking.
- Bake the room/world, open generated scenes read-only, and visually compare tile/content alignment.
- Run the inherited room directly, then start it through the bilingual menu and test fog, transition, save/load, and respawn.

**Agent follow-up:**
- [ ] Address concrete editor error logs supplied by the user using the systematic-debugging workflow.
- [ ] Run final automated verification:

```powershell
godot --headless --path . -s res://tests/run_runtime_suite.gd
godot --headless --path . -s res://tools/validate_project.gd
godot --headless --path . res://scenes/main.tscn --quit-after 5
git diff --check
```

- [ ] Confirm `docs/todo.md` and authored tile placement were not changed.
- [ ] Report generated assets, validation results, manual checks completed by the user, and any remaining non-blocking warnings.

## Delivery Boundaries

Implementation is complete only after Tasks 1-12 and the user-owned editor checkpoints pass. The first implementation run should stop at Task 5 for scene migration, then continue automatically after the user confirms the inherited scene. The second manual stop is Task 12 visual acceptance. All other tasks are agent-owned and should be carried through without additional scope questions.
