# Foundation Level System Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace legacy level paths and compatibility state with one fully baked, WorldData-owned level system suitable for reuse.

**Architecture:** WorldData owns placement and transitions, RoomData owns only room-local generated metadata, and generated assets live under one directory per room. Persistent entities write through a runtime-provided state sink; WorldSession supplies bounds to a selectable camera mode and room-local fog.

**Tech Stack:** Godot 4.7.2, typed GDScript, Godot Resource/PackedScene serialization, plain GDScript runtime tests.

**Spec:** `docs/superpowers/specs/2026-09-07-foundation-level-system-migration-design.md`

## Global Constraints

- Do not alter tile cell placement, user-authored room content, `docs/todo.md`, or `AGENTS.md`.
- Work directly on branch `level0`; do not create a worktree or commit automatically.
- Remove legacy runtime paths after all references and tests use their replacements.
- Preserve the user's current World editor and terrain-preview changes while moving files.
- Run focused tests before and after every behavior change; register new tests in `tests/runtime_suite.gd`.

---

### Task 1: Establish the final room-grid and resource contracts

**Files:**
- Create: `scripts/world/data/room_grid.gd`
- Modify: `scripts/world/room_data.gd`, `scripts/world/world_data.gd`, `scripts/world/room_runtime.gd`
- Test: `tests/world/data/test_room_grid.gd`, `tests/world/runtime/test_room_runtime.gd`

**Interfaces:**
- Produces `RoomGrid.get_cells_per_chunk(cell_size, chunk_size_pixels) -> Vector2i`.
- Produces `RoomGrid.get_room_cell_rect(origin_chunk, room_size_chunks, cell_size, chunk_size_pixels) -> Rect2i`.
- Removes `RoomData.room_origin_chunk`, `RoomData.adjacent_room_ids`, and their spatial helpers.

- [ ] **Step 1: Write exact-cell tests**

```gdscript
var rect := RoomGrid.get_room_cell_rect(Vector2i(2, 1), Vector2i(3, 2))
if rect != Rect2i(80, 23, 120, 45):
    failures.append("multi-chunk room cell rect must use exact 720x360 pixel extent")
```

Add tests that RoomData has no legacy origin/adjacency properties and that
WorldData provides the room chunk/pixel/cell rectangles.

- [ ] **Step 2: Run RED tests**

Run: `godot --headless --path . -s res://tests/run_test_script.gd -- res://tests/world/data/test_room_grid.gd`

Expected: missing RoomGrid API and legacy fields still present.

- [ ] **Step 3: Implement the new grid API and data ownership**

```gdscript
static func get_room_cell_rect(origin: Vector2i, size: Vector2i, cell := Vector2i(8, 8), chunk := Vector2i(320, 180)) -> Rect2i:
    var cells_per_chunk := get_cells_per_chunk(cell, chunk)
    var size_pixels := size * chunk
    return Rect2i(origin * cells_per_chunk, Vector2i(ceili(float(size_pixels.x) / cell.x), ceili(float(size_pixels.y) / cell.y)))
```

Make RoomRuntime require an explicit WorldData origin and delegate cell-rect
calculation to RoomGrid. Remove legacy migration/adjacency reads from WorldData,
WorldValidation, WorldLayoutModel, RoomBaker, and WorldResourceService.

- [ ] **Step 4: Run GREEN tests**

Run focused data/runtime tests and `tests/world/test_world_data.gd`.

### Task 2: Make persistent entity state durable

**Files:**
- Modify: `scripts/world/world_entity.gd`, `scripts/world/pickup_entity.gd`, `scripts/world/switch_entity.gd`, `scripts/world/save_point.gd`, `scripts/world/room_runtime.gd`, `scripts/world/world_runtime.gd`, `scripts/save/save_snapshot.gd`
- Test: `tests/world/entities/test_entity_persistence.gd`, `tests/save/test_save_codec.gd`

**Interfaces:**
- Produces `WorldEntity.commit_save_state() -> bool`.
- Produces `RoomRuntime.persist_entity_states() -> void`.
- Produces `WorldRuntime.persist_loaded_entity_states() -> void`.

- [ ] **Step 1: Write failing persistence tests**

```gdscript
pickup.collect()
runtime.persist_entity_states()
if snapshot.get_entity_state("world_a:room_a:pickup").get("collected") != true:
    failures.append("collected pickup state was not persisted")
```

Cover switch/save-point immediate writes, room unload/reload, and loading a
second SaveSnapshot without retained explored chunks or entity states.

- [ ] **Step 2: Run RED tests**

Run: `godot --headless --path . -s res://tests/run_test_script.gd -- res://tests/world/entities/test_entity_persistence.gd`

Expected: entity state is absent after mutation/unload.

- [ ] **Step 3: Implement state sinks and atomic snapshot replacement**

Pass separate read source and write sink through RoomRuntime setup. Persistent
entities store the sink during `setup_entity(context)`; their mutations call
`commit_save_state()`. Before WorldRuntime frees any room, call
`persist_entity_states()`. Have SaveManager announce an imminent snapshot write
and bind WorldRuntime to flush all loaded entities before that write. Parse
SaveSnapshot input into temporary dictionaries, then replace every stored
collection only after validation succeeds.

- [ ] **Step 4: Run GREEN tests**

Run entity, room-runtime, world-runtime, save-codec, and save-storage tests.

### Task 3: Correct selectable camera and room-local fog behavior

**Files:**
- Modify: `scripts/camera/pixel_camera_2d.gd`, `scripts/world/world_session.gd`, `scripts/world/fog_of_war.gd`, `scripts/world/fog_visibility.gd`
- Test: `tests/world/runtime/test_pixel_camera.gd`, `tests/world/fog/test_fog_visibility.gd`, `tests/world/runtime/test_world_session.gd`

**Interfaces:**
- `PixelCamera2D.set_room_bounds(bounds: Rect2) -> void` never changes `camera_mode`.
- `PixelCamera2D.clear_room_bounds() -> void` removes bounds without changing the authored mode.
- `FogOfWar` retains only `VisionBlockTiles` as a blocker dependency.

- [ ] **Step 1: Write failing mode and clamp tests**

```gdscript
camera.camera_mode = PixelCamera2D.CameraMode.FREE
camera.set_room_bounds(Rect2(Vector2.ZERO, Vector2(320, 180)))
if camera.camera_mode != PixelCamera2D.CameraMode.FREE:
    failures.append("supplying room bounds changed free camera mode")
```

Add a room-change case proving an old out-of-bounds smoothed position is
clamped immediately. Add fog assertions that Solid/Glass are not bound or
warned about and that only current visibility clears mask pixels.

- [ ] **Step 2: Run RED tests**

Run focused camera, fog, and session tests.

- [ ] **Step 3: Implement mode-respecting bounds**

Make WorldRoot explicitly choose ROOM_LOCKED and source-room preview explicitly
choose FREE. WorldSession only supplies a room rectangle. Remove obsolete
Solid/Glass fog paths/fields and rename missing-layer diagnostics to
VisionBlockTiles.

- [ ] **Step 4: Run GREEN tests**

Run focused tests and direct headless startup of WorldRoot.

### Task 4: Add source fingerprints and strict Bake validation

**Files:**
- Modify: `scripts/world/room_data.gd`, `scripts/authoring/room_baker.gd`, `scripts/authoring/world_baker.gd`, `addons/wellwell_world_editor/world_editor_main.gd`
- Test: `tests/authoring/room/test_room_baker.gd`, `tests/authoring/world/test_world_baker.gd`

**Interfaces:**
- Adds `RoomData.source_fingerprint: String`.
- Produces `RoomBaker.get_source_fingerprint(source_path: String) -> String`.
- WorldBaker rejects a RoomData whose source fingerprint differs from the saved source scene.

- [ ] **Step 1: Write failing stale-output test**

```gdscript
room.source_fingerprint = "outdated"
var result := WorldBaker.new().bake(world)
if result.get("ok", true):
    failures.append("Bake World accepted a stale generated room")
```

- [ ] **Step 2: Run RED tests**

Run focused room/world baker tests.

- [ ] **Step 3: Implement fingerprints**

Use `FileAccess.get_sha256(source_path)` for saved authoring scenes. RoomBaker
writes the fingerprint into staged RoomData; WorldBaker compares it before
persisting WorldData. World editor reports the first stale room and leaves the
active WorldData untouched.

- [ ] **Step 4: Run GREEN tests**

Run focused baker/importer/editor command tests.

### Task 5: Move production scripts and update path references

**Files:**
- Move: app scripts to `scripts/app/`; world scripts to `scripts/world/data/`, `runtime/`, `entities/`, and `fog/`; authoring scripts to `scripts/authoring/room/` and `world/`
- Modify: every `.gd`, `.tscn`, `.tres`, `project.godot`, plugin script, and test preload referencing moved paths
- Test: all runtime tests

- [ ] **Step 1: Add final-layout reference test**

```gdscript
for path in REQUIRED_PRODUCTION_PATHS:
    if not ResourceLoader.exists(path):
        failures.append("missing migrated production path: %s" % path)
```

Assert the old script paths do not exist and every class can load from its new
location.

- [ ] **Step 2: Run RED test**

Run the new final-layout test before the moves.

- [ ] **Step 3: Move files and mechanically update references**

Use explicit `Move-Item -LiteralPath` targets after verifying every source and
destination. Update all direct `preload()`, `load()`, script inheritance,
scene ext_resource paths, plugin configuration, and test constants. Retain
`.uid` sidecars beside each moved script. Remove the orphaned `Globals` autoload
and the unused camera-position compatibility code only after the reference
search proves no remaining consumer.

- [ ] **Step 4: Run GREEN tests**

Run editor initialization and the full runtime suite. Search for old script
paths and require zero production references.

### Task 6: Move scenes/resources and re-bake four shipped rooms

**Files:**
- Move: `scenes/main.tscn` to `scenes/app/main.tscn`, WorldRoot to `scenes/runtime/world_root.tscn`, level sources to `scenes/rooms/source/`
- Move: generated outputs to per-room directories and generated RoomData to `resources/rooms/generated/<room_id>.tres`
- Create: `resources/worlds/main_world.tres`
- Remove: legacy `scenes/game.tscn`, `scenes/rooms/room_template.tscn`, `resources/rooms/template_room.tres`, `resources/worlds/template_world.tres`, and `resources/worlds/level_0_world.tres`
- Test: `tests/world/runtime/test_world_session.gd`, `tests/authoring/world/test_world_editor_commands.gd`

- [ ] **Step 1: Add a migrated-world fixture test**

Assert main.tscn points to the moved WorldRoot, WorldRoot points to main_world,
main_world includes level_0 through level_3, and every RoomData source/runtime/
terrain path is in the final layout.

- [ ] **Step 2: Run RED test**

Run the fixture test and confirm it identifies old paths.

- [ ] **Step 3: Move assets and produce final generated resources**

Move all generated artifacts into each room's directory, update
`RoomBakePaths`, re-bake the four saved source scenes, and create
`main_world.tres` with the four generated resources, explicit placements, and
the existing valid start endpoint. Update `run/main_scene`.

- [ ] **Step 4: Remove old assets after validation**

Use `rg` to prove no production reference targets a legacy asset, then remove
only the listed legacy files. Preserve level source tile bytes before/after the
move and fail the migration test if they differ.

- [ ] **Step 5: Run GREEN tests**

Run WorldSession, terrain runtime, world runtime, editor command tests, and
direct startup of main plus each source room.

### Task 7: Complete World editor migration and test cleanup

**Files:**
- Modify: `addons/wellwell_world_editor/world_editor_main.tscn`, plugin scripts, moved authoring tests, `tests/runtime_suite.gd`
- Test: `tests/authoring/world/test_world_editor_commands.gd`, `tests/authoring/world/test_world_canvas_view.gd`

- [ ] **Step 1: Write explicit dialog/configuration tests**

```gdscript
if dialog.access != FileDialog.ACCESS_RESOURCES or dialog.file_mode != FileDialog.FILE_MODE_SAVE_FILE:
    failures.append("New World dialog must save a resource under res://resources/worlds")
```

Replace the stale `preview_spawn_id == "start"` assertion with equality to the
actual source SpawnPoint ID.

- [ ] **Step 2: Run RED test**

Run the moved World editor command test.

- [ ] **Step 3: Configure the main-screen dialogs and paths**

Set both dialogs to resource access; set Add Existing to source room scenes and
New World to save a `.tres` below `res://resources/worlds`. Ensure all editor
commands use moved source/generated paths and stale-bake errors appear in Status.

- [ ] **Step 4: Run GREEN tests**

Run all authoring tests and editor headless initialization.

### Task 8: Publish the new project map and verify the foundation

**Files:**
- Modify: `README.md`, `docs/extension-guide.md`, `tools/validate_project.gd`
- Create: `docs/project-structure.md`
- Test: `tests/tools/test_project_validation.gd`

- [ ] **Step 1: Write the production-path validation test**

Replace the old game-scene validation with the generated terrain contract and
assert that `main_world.tres` validates through WorldValidation.

- [ ] **Step 2: Run RED test**

Run: `godot --headless --path . -s res://tests/run_test_script.gd -- res://tests/tools/test_project_validation.gd`

- [ ] **Step 3: Update documentation and validation tool**

Document the source-to-bake-to-world workflow, canonical directories, one-world
example, explicit bake order, and removal of old entry points. Make the command
line validation tool load main_world and every generated terrain scene.

- [ ] **Step 4: Final verification**

Run:

```powershell
godot --headless --path . -s res://tests/run_runtime_suite.gd
godot --headless --editor --path . --quit
godot --headless --path . --quit-after 5
git diff --check
rg -n "res://scenes/game.tscn|res://scripts/world/[^/]+\\.gd|res://scripts/authoring/[^/]+\\.gd" scripts scenes resources addons tests tools project.godot
```

The final search may match historical `docs/superpowers` records only; it must
produce no production/test references to legacy paths.
