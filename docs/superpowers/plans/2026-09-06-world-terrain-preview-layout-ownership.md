# World Terrain Preview and Layout Ownership Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move world-specific room origins into embedded WorldData placements, unify reliable world persistence, and render generated terrain tiles in the World Editor canvas.

**Architecture:** WorldData becomes authoritative for placement through embedded WorldRoomPlacementData resources and compatibility normalization from legacy RoomData coordinates. Runtime and authoring systems consume WorldData spatial APIs. The editor instantiates filtered, clipped generated terrain scenes beneath a separate overlay layer, while Save World and Bake World share one staged, UID-aware persistence service.

**Tech Stack:** Godot 4.7.2, typed GDScript, Resource/PackedScene/TileMapLayer, EditorPlugin main-screen UI, plain GDScript runtime tests.

**Spec:** `docs/superpowers/specs/2026-09-06-world-terrain-preview-layout-ownership-design.md`

## Global Constraints

- Work directly on the current `level0` branch; do not create a worktree.
- Do not edit `scenes/levels/level_0.tscn`, `level_1.tscn`, `level_2.tscn`, `scenes/templates/level_template.tscn`, authored tile data, or `docs/todo.md`.
- Do not overwrite unrelated user changes or regenerate user-authored scenes during tests.
- Use generated `RoomData.terrain_scene_path` only; the preview never opens or mutates room source scenes.
- Keep `RoomData.room_origin_chunk` only as a legacy fallback. New behavior must use WorldData placement APIs.
- Visual Godot acceptance belongs to the user. Automated tests verify resource, node, transform, and persistence contracts.
- Do not commit automatically in the current dirty workspace. Each task ends with a focused verification checkpoint.

---

### Task 1: Embedded World Room Placements

**Files:**
- Create: `scripts/world/world_room_placement_data.gd`
- Modify: `scripts/world/world_data.gd`
- Modify: `scripts/world/room_data.gd`
- Test: `tests/world/test_world_data.gd`

**Interfaces:**
- Produces: `WorldRoomPlacementData` with `room_id: String` and `origin_chunk: Vector2i`.
- Produces: `WorldData.get_room_placement(room_id)`, `get_room_origin_chunk(room_id)`, `set_room_origin_chunk(room_id, origin)`, `get_room_chunk_rect(room_id)`, `get_room_pixel_rect(room_id)`, and `normalize_room_placements()`.
- Compatibility: missing placements read legacy `RoomData.room_origin_chunk`; existing placements always win.

- [ ] **Step 1: Write failing placement and migration tests**

Add cases proving a placement overrides the legacy coordinate, normalization creates one placement per missing room, duplicate/unknown placement IDs fail without deletion, and two worlds can place one shared RoomData differently.

```gdscript
var shared_room := _make_room("shared", Vector2i(7, 3))
var world_a := _make_world([shared_room])
var world_b := _make_world([shared_room])
world_a.normalize_room_placements()
world_b.normalize_room_placements()
world_a.set_room_origin_chunk("shared", Vector2i(-1, -1))
world_b.set_room_origin_chunk("shared", Vector2i(4, 2))
if world_a.get_room_origin_chunk("shared") != Vector2i(-1, -1):
	failures.append("world A placement was not authoritative")
if world_b.get_room_origin_chunk("shared") != Vector2i(4, 2):
	failures.append("world B placement was not independent")
```

- [ ] **Step 2: Run RED test**

Run:

```powershell
& 'D:/Godot4/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe' --headless --path . -s res://tests/run_test_script.gd -- res://tests/world/test_world_data.gd
```

Expected: failure because placement APIs and resource do not exist.

- [ ] **Step 3: Implement the placement resource and WorldData APIs**

Store placements as `@export var placements: Array[Resource] = []`, validate exact script identity, sort by room ID, and return an envelope from normalization:

```gdscript
{"ok": errors.is_empty(), "errors": errors, "warnings": warnings, "created_count": created_count}
```

Make `get_room_ids_at_chunk()`, resident-room discovery, and world rect helpers use placement-aware rectangles. Add a deprecation comment to RoomData; do not remove the field or legacy methods.

- [ ] **Step 4: Run GREEN test and runtime consumers that compile WorldData**

Run focused `test_world_data.gd`, `test_map_model.gd`, and `test_world_runtime.gd`. Expected: placement tests pass; legacy tests remain green through fallback behavior.

### Task 2: Authoring Operations and Optional Connection Validation

**Files:**
- Modify: `scripts/authoring/world_layout_model.gd`
- Modify: `scripts/authoring/world_room_importer.gd`
- Modify: `scripts/world/world_validation.gd`
- Test: `tests/authoring/test_world_layout_model.gd`
- Test: `tests/authoring/test_world_room_importer.gd`
- Test: `tests/authoring/test_world_editor_commands.gd`
- Test: `tests/world/test_world_validation.gd`

**Interfaces:**
- Changes: `WorldLayoutModel.add_room(world, room, origin_chunk := Vector2i.ZERO)` creates membership and placement together.
- Changes: move/remove/replace/capture/restore operate on placements; RoomData coordinates are not mutated.
- Changes: reachability warnings run only when at least one valid connection exists.

- [ ] **Step 1: Write failing model, importer, undo, and validation tests**

Assert that moving changes only WorldData placement, removing clears it, replacement preserves it, and captured states deep-copy placements. Use the real importer result to assert an empty world's first room is `(0, 0)` and a non-empty world's next room is `(-1, -1)`. Add validation cases for zero connections and for a directed graph with an unreachable room.

- [ ] **Step 2: Run RED tests**

Run the four focused scripts. Expected failures mention missing placements, RoomData being mutated, wrong import origin, or unwanted no-connection reachability warnings.

- [ ] **Step 3: Implement placement-aware authoring mutations**

Normalize before mutation. Add room and placement as one operation, choose import origin before `add_room`, remove both atomically, and preserve placement when replacing a baked RoomData reference. Deep-duplicate placement resources in capture/restore so Undo/Redo cannot alias later mutations.

- [ ] **Step 4: Update validation**

Validate exactly one placement for every room and calculate overlaps with `world.get_room_chunk_rect(room_id)`. Build reachability only from valid directed connections; skip the unreachable pass when no valid connection records exist. Keep start endpoint and malformed connection checks unchanged.

- [ ] **Step 5: Run GREEN tests**

Expected: all four focused scripts exit 0 and import rollback tests leave no `.stage`, `.backup`, or `.import_backup` files.

### Task 3: One UID-Aware World Persistence Transaction

**Files:**
- Modify: `scripts/authoring/world_resource_service.gd`
- Modify: `scripts/authoring/world_baker.gd`
- Modify: `addons/wellwell_world_editor/world_editor_main.gd`
- Test: `tests/authoring/test_world_resource_service.gd`
- Test: `tests/authoring/test_world_baker.gd`
- Test: `tests/authoring/test_world_editor_commands.gd`

**Interfaces:**
- Produces: `WorldResourceService.save_candidate()` normalizes placements, stages, compares, promotes with UID synchronization, reloads, and returns the final WorldData.
- Produces: a recursive first-difference description for world signature mismatches.
- Changes: `WorldBaker.bake()` validates generated artifacts then delegates saving to WorldResourceService.

- [ ] **Step 1: Write failing persistence regression tests**

Cover drag/save/reload placement equality, embedded placement serialization, stale stage UID cleanup, stage-to-final UID remapping, rollback restoration, and a mismatch message naming `placements.<room_id>.origin_chunk`. Add a WorldBaker case using external RoomData and changed placement, since embedded-room fixtures do not reproduce the current failure.

- [ ] **Step 2: Run RED tests**

Run the three focused scripts. Expected: reload loses placement or reports the current generic mismatch, and WorldBaker's independent transaction remains observable.

- [ ] **Step 3: Extend the stable world signature**

Include sorted placement dictionaries and exclude legacy RoomData origin. Implement a recursive comparator that traverses dictionaries in sorted key order and arrays by index, returning the first path and expected/actual values.

- [ ] **Step 4: Harden the shared transaction**

Normalize a deep candidate, remove stale stage UID mappings, save and reload the stage, back up the final, promote while remapping ResourceUID, reload the final, and restore on any failure. Never mutate the active WorldData's `resource_path` by saving it directly to the stage path.

- [ ] **Step 5: Delegate WorldBaker persistence**

Retain WorldBaker artifact validation but remove its duplicate save/backup/promote implementation. Call the shared service and preserve warnings in the common result envelope. Make both Save World and Bake World adopt the returned final resource.

- [ ] **Step 6: Run GREEN tests and diff check**

Expected: all focused persistence tests exit 0; `git diff --check` exits 0 apart from line-ending notices.

### Task 4: Runtime Placement Integration

**Files:**
- Modify: `scripts/world/room_runtime.gd`
- Modify: `scripts/world/world_runtime.gd`
- Modify: `scripts/world/world_terrain_runtime.gd`
- Modify: `scripts/world/world_session.gd`
- Modify: `scripts/world/fog_of_war.gd`
- Modify: `scripts/world/map_model.gd`
- Test: `tests/world/test_room_runtime.gd`
- Test: `tests/world/test_world_runtime.gd`
- Test: `tests/world/test_world_terrain_runtime.gd`
- Test: `tests/world/test_fog_visibility.gd`
- Test: `tests/world/test_map_model.gd`

**Interfaces:**
- Changes: `RoomRuntime.setup_room(..., origin_chunk: Variant = null)` stores an explicit placement and falls back to legacy RoomData only for old direct callers.
- Changes: `FogOfWar.bind_room(room_data, terrain_root, origin_chunk: Variant = null)` accepts the world origin explicitly.
- Changes: WorldRuntime, WorldTerrainRuntime, WorldSession, and MapModel pass/query WorldData placement coordinates.

- [ ] **Step 1: Write failing runtime placement tests**

Use a RoomData whose legacy origin differs from its WorldData placement. Assert runtime content, persistent terrain, map rect/chunk IDs, resident room discovery, and fog mask origin all follow the WorldData value.

- [ ] **Step 2: Run RED tests**

Expected: at least room runtime, terrain runtime, map, and fog assertions report the legacy coordinate.

- [ ] **Step 3: Implement explicit origin propagation**

Store `_origin_chunk` in RoomRuntime and derive chunk/cell rects from it. WorldRuntime obtains the origin from WorldData when staging each room. WorldTerrainRuntime signatures and instance positions use WorldData APIs. WorldSession passes the active room placement into fog binding. MapModel builds rects and chunk IDs from world placement rather than RoomData helpers.

- [ ] **Step 4: Run GREEN runtime tests**

Expected: all five focused scripts exit 0, including legacy fallback tests that call RoomRuntime or FogOfWar without the new optional argument.

### Task 5: Read-Only Terrain Preview Layer

**Files:**
- Create: `addons/wellwell_world_editor/world_terrain_preview_layer.gd`
- Create: `addons/wellwell_world_editor/world_layout_overlay.gd`
- Modify: `addons/wellwell_world_editor/world_editor_main.tscn`
- Modify: `addons/wellwell_world_editor/world_layout_canvas.gd`
- Test: `tests/authoring/test_world_terrain_preview_layer.gd`
- Test: `tests/authoring/test_world_canvas_view.gd`
- Modify: `tests/runtime_suite.gd`

**Interfaces:**
- Produces: preview methods `sync_world(world)`, `refresh_room(world, room_id)`, `remove_room(room_id)`, `set_view_transform(center_world, zoom, viewport_size)`, and `set_drag_origin(room_id, origin_or_null)`.
- Produces: overlay setters for canvas/main references and redraw forwarding.
- Consumes: RoomData terrain path/size and WorldData placement APIs.

- [ ] **Step 1: Write failing preview structure and filtering tests**

Build a temporary PackedScene containing Background, the six semantic TileMapLayers, and an extra CanvasItem. Assert one clipped container is created at the placement pixel origin, its size matches room chunks, only the five allowed tile layers remain visible, MarkerTiles is hidden, collision/navigation/processing/input are disabled, and invalid terrain produces a recorded preview error without preventing other rooms.

- [ ] **Step 2: Run RED preview tests**

Expected: missing preview layer script or missing methods.

- [ ] **Step 3: Implement TerrainPreviewLayer**

Load with `CACHE_MODE_IGNORE`, instantiate one scene per room, clip each container, filter visibility recursively, and retain a dictionary keyed by room ID. Synchronization removes obsolete rooms and only rebuilds new or changed terrain paths. View updates set one root position/scale; drag updates one container.

- [ ] **Step 4: Split visual ordering**

Keep background and grid drawing in WorldLayoutCanvas. Move room fills/frames, labels, connection arrows, start marker, cursor text, overlap tint, and drag guides into the input-transparent overlay. Add `TerrainPreviewLayer` and `OverlayLayer` below/above each other in the main-screen scene with full-rect sizing.

- [ ] **Step 5: Preserve canvas interaction**

Update hit testing, Focus All, Focus Room, drag previews, pan, zoom, and resize notifications to use WorldData placement and synchronize both child layers. Terrain and overlay children must use `MOUSE_FILTER_IGNORE` so LayoutCanvas remains the sole input owner.

- [ ] **Step 6: Run GREEN preview tests**

Expected: preview and canvas tests exit 0; scene-state main-screen test confirms the layer nodes and scripts exist.

### Task 6: Editor Lifecycle and Selective Refresh

**Files:**
- Modify: `addons/wellwell_world_editor/world_editor_main.gd`
- Modify: `addons/wellwell_world_editor/world_editor_plugin.gd`
- Test: `tests/authoring/test_world_editor_commands.gd`
- Test: `tests/authoring/test_world_editor_main_screen.gd`

**Interfaces:**
- Changes: setting/switching a world normalizes placements and synchronizes previews.
- Changes: Add Existing adds one preview; Bake Room refreshes one preview; move/Undo/Redo update transforms; plugin teardown clears instances.

- [ ] **Step 1: Write failing lifecycle tests**

Use a preview adapter to assert full sync on world selection, one-room refresh after Bake Room, no terrain reload during move, removal cleanup, and clear on plugin/main-screen teardown. Assert migration warnings reach the status tooltip without blocking editing.

- [ ] **Step 2: Run RED lifecycle tests**

Expected: preview adapter receives no calls and migration status is absent.

- [ ] **Step 3: Wire lifecycle events**

Have `_refresh()` redraw overlays and placement transforms without full scene reload. Call full preview sync only for world identity/membership changes, selective refresh after Bake Room, and clear before freeing the main screen. Keep command busy states and import history behavior intact.

- [ ] **Step 4: Run GREEN lifecycle tests**

Expected: both focused editor scripts exit 0 and no editor-only control is instantiated in a runtime-only test.

### Task 7: Integrated Verification and Documentation Status

**Files:**
- Modify: `docs/superpowers/specs/2026-09-05-level-authoring-world-editor-design.md`
- Modify: `docs/superpowers/specs/2026-09-06-world-editor-main-screen-redesign.md`
- Modify: `.superpowers/sdd/2026-09-05-level-authoring-world-editor/progress.md`

**Interfaces:**
- Documents the new spec as authoritative for placements, preview, persistence, and optional reachability.
- Records automated evidence and the user's remaining visual checklist.

- [ ] **Step 1: Run every focused test changed by Tasks 1-6**

Expected: all authoring/world focused scripts exit 0 with sandbox-external execution where `user://` fixtures require it.

- [ ] **Step 2: Run the complete runtime suite**

```powershell
& 'D:/Godot4/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe' --headless --log-file '.godot/final_suite.log' --path . -s res://tests/run_runtime_suite.gd
```

Record every remaining failure exactly. Do not change user-owned scenes to satisfy fixture assumptions.

- [ ] **Step 3: Run editor parse and main-scene startup checks**

Run headless editor initialization with `--quit-after 5` and start `res://scenes/main.tscn` headlessly. Expected: no script parse errors, placeholder-script calls, or missing generated-resource failures.

- [ ] **Step 4: Audit files and temporary outputs**

Run `git diff --check`, verify no transaction files remain under `resources/` or `scenes/`, and confirm protected scenes and `docs/todo.md` were not changed by this implementation.

- [ ] **Step 5: Update supersession and progress notes**

Add concise links from old specs to the new authoritative document. Record test commands/results and leave the eight-step manual Godot terrain-preview acceptance checklist assigned to the user.

