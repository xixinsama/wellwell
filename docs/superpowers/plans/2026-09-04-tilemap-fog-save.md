# Tilemap Fog Save Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the graybox platform level with an 8x8 `TileMapLayer` test map, add wall-blocked exploration fog, and persist discovered cells through a lightweight save system.

**Architecture:** Keep player movement unchanged. Add a small save stack modeled after `after-blast`, a pure fog visibility helper for testing, a `FogOfWar` drawing controller, and a layered tilemap scene. The fog controller reads the solid tile layer for line-of-sight blockers and writes explored cell IDs to `SaveManager`.

**Tech Stack:** Godot 4.7, GDScript, `TileMapLayer`, `TileSet`, `Node2D._draw`, JSON files in `user://`.

**Spec:** `docs/superpowers/specs/2026-09-04-tilemap-fog-save-design.md`

## Global Constraints

- Use Godot 4.7 `TileMapLayer` rather than legacy `TileMap` authoring patterns.
- Preserve the existing 320x180 safe gameplay frame inside the 322x182 `SubViewport`.
- Keep `PlayerController` responsible for movement and respawn; do not move gameplay control into fog or save code.
- `SolidTiles` uses TileSet physics layer 0 and collision layer bit 1 (`world`).
- Fog cells use 8x8 world units and stable IDs like `level_01:12,-4`.
- Unexplored cells render opaque black; explored cells render transparent in the first implementation.
- Use one save slot by default, while keeping slot arguments for future expansion.
- Save game progress under `user://saves/slot_1.json` with `.tmp` and `.backup.json` handling.
- Save settings separately under `user://settings.json`; no settings UI in this pass.
- Do not add save-slot menus, preview screenshots, minimaps, room streaming, dynamic fog textures, enemies, pickups, combat, progression gates, or editor baking tools.

---

## File Structure

- Create `scripts/save/save_snapshot.gd`: versioned save data, dictionary conversion, validation.
- Create `scripts/save/save_codec.gd`: JSON encode/decode wrapper.
- Create `scripts/save/save_storage.gd`: atomic slot write/read/delete with backup fallback.
- Create `scripts/save/save_manager.gd`: autoload-facing one-slot progress manager and debounced commits.
- Create `scripts/save/global_settings_store.gd`: small dictionary persistence for settings.
- Create `scripts/save/global_settings_manager.gd`: autoload-facing settings defaults and getters/setters.
- Create `scripts/world/fog_visibility.gd`: pure static grid line-of-sight and reveal calculation helpers.
- Create `scripts/world/fog_of_war.gd`: `Node2D` runtime controller that draws fog and talks to `SaveManager`.
- Create `resources/tilesets/template_platform_tileset.tres`: 8x8 tile definitions with solid collision.
- Modify `scenes/game.tscn`: replace graybox bodies with `BackTiles`, `SolidTiles`, `DetailTiles`, and `FogOfWar`.
- Modify `project.godot`: register `SaveManager` and `GlobalSettings` autoloads.
- Create `tests/runtime_suite.gd`: minimal headless test runner.
- Create `tests/save/test_save_codec.gd`: save snapshot and codec tests.
- Create `tests/save/test_save_storage.gd`: storage primary/backup tests.
- Create `tests/world/test_fog_visibility.gd`: fog line-of-sight and exploration tests.
- Create `tests/run_runtime_suite.gd`: scene-tree launcher for command-line tests.

### Task 1: Save Snapshot and Codec

**Files:**
- Create: `scripts/save/save_snapshot.gd`
- Create: `scripts/save/save_codec.gd`
- Create: `tests/save/test_save_codec.gd`
- Create: `tests/runtime_suite.gd`
- Create: `tests/run_runtime_suite.gd`

**Interfaces:**
- Produces: `SaveSnapshot.to_dictionary() -> Dictionary`
- Produces: `static SaveSnapshot.from_dictionary(data: Dictionary) -> SaveSnapshot`
- Produces: `SaveSnapshot.add_explored_cell(cell_id: String) -> bool`
- Produces: `SaveSnapshot.has_explored_cell(cell_id: String) -> bool`
- Produces: `SaveSnapshot.get_explored_cells() -> Array[String]`
- Produces: `static SaveCodec.encode(snapshot: SaveSnapshot) -> String`
- Produces: `static SaveCodec.decode(text: String, expected_slot: int) -> SaveSnapshot`

- [ ] **Step 1: Write the failing codec test**

```gdscript
# tests/save/test_save_codec.gd
extends Node

const SAVE_SNAPSHOT := preload("res://scripts/save/save_snapshot.gd")
const SAVE_CODEC := preload("res://scripts/save/save_codec.gd")


func run() -> Array[String]:
    var failures: Array[String] = []
    _assert_round_trip_preserves_explored_cells(failures)
    _assert_invalid_data_is_rejected(failures)
    return failures


func _assert_round_trip_preserves_explored_cells(failures: Array[String]) -> void:
    var snapshot := SAVE_SNAPSHOT.new()
    snapshot.slot = 1
    snapshot.respawn_position = Vector2(-120, 48)
    snapshot.add_explored_cell("level_01:-15,6")
    snapshot.add_explored_cell("level_01:-14,6")
    snapshot.add_explored_cell("level_01:-15,6")

    var decoded := SAVE_CODEC.decode(SAVE_CODEC.encode(snapshot), 1)

    if decoded == null:
        failures.append("decoded snapshot was null")
        return
    if decoded.slot != 1:
        failures.append("slot did not round trip")
    if decoded.respawn_position != Vector2(-120, 48):
        failures.append("respawn position did not round trip")
    if decoded.get_explored_cells() != ["level_01:-14,6", "level_01:-15,6"]:
        failures.append("explored cells were not unique and sorted")


func _assert_invalid_data_is_rejected(failures: Array[String]) -> void:
    if SAVE_CODEC.decode("{not valid json", 1) != null:
        failures.append("invalid JSON decoded")
    if SAVE_CODEC.decode("[]", 1) != null:
        failures.append("non-dictionary JSON decoded")
    var snapshot := SAVE_SNAPSHOT.new()
    snapshot.slot = 2
    if SAVE_CODEC.decode(SAVE_CODEC.encode(snapshot), 1) != null:
        failures.append("mismatched slot decoded")
```

```gdscript
# tests/runtime_suite.gd
extends Node

const TESTS: Array[Script] = [
    preload("res://tests/save/test_save_codec.gd"),
]


func run() -> bool:
    var failures: Array[String] = []
    for test_script: Script in TESTS:
        var test := test_script.new()
        add_child(test)
        failures.append_array(test.run())
        test.queue_free()
    for failure: String in failures:
        push_error(failure)
    return failures.is_empty()
```

```gdscript
# tests/run_runtime_suite.gd
extends SceneTree


func _init() -> void:
    var suite := preload("res://tests/runtime_suite.gd").new()
    root.add_child(suite)
    quit(0 if suite.run() else 1)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `& 'D:\Godot4\src\godot\bin\godot.windows.editor.x86_64.mono.console.exe' --headless --path . -s res://tests/run_runtime_suite.gd`

Expected: FAIL because `scripts/save/save_snapshot.gd` and `scripts/save/save_codec.gd` do not exist.

- [ ] **Step 3: Implement snapshot and codec**

```gdscript
# scripts/save/save_snapshot.gd
class_name SaveSnapshot
extends RefCounted

const FORMAT_VERSION := 1

var slot := 1
var respawn_position := Vector2.ZERO
var saved_unix_time := 0
var _explored_cells: Dictionary[String, bool] = {}


func add_explored_cell(cell_id: String) -> bool:
    if cell_id.is_empty() or _explored_cells.has(cell_id):
        return false
    _explored_cells[cell_id] = true
    return true


func has_explored_cell(cell_id: String) -> bool:
    return _explored_cells.has(cell_id)


func get_explored_cells() -> Array[String]:
    var result: Array[String] = []
    result.assign(_explored_cells.keys())
    result.sort()
    return result


func to_dictionary() -> Dictionary:
    return {
        "format_version": FORMAT_VERSION,
        "slot": slot,
        "respawn_position": {"x": respawn_position.x, "y": respawn_position.y},
        "explored_cells": get_explored_cells(),
        "saved_unix_time": saved_unix_time,
    }


static func from_dictionary(data: Dictionary) -> SaveSnapshot:
    if int(data.get("format_version", -1)) != FORMAT_VERSION:
        return null
    var parsed_slot := int(data.get("slot", 0))
    if parsed_slot < 1 or parsed_slot > 3:
        return null
    var position_data: Variant = data.get("respawn_position", null)
    if not position_data is Dictionary:
        return null
    if not position_data.has("x") or not position_data.has("y"):
        return null
    var explored_data: Variant = data.get("explored_cells", [])
    if not explored_data is Array:
        return null

    var result := SaveSnapshot.new()
    result.slot = parsed_slot
    result.respawn_position = Vector2(float(position_data["x"]), float(position_data["y"]))
    result.saved_unix_time = int(data.get("saved_unix_time", 0))
    for value: Variant in explored_data:
        if not value is String:
            return null
        result.add_explored_cell(value)
    return result
```

```gdscript
# scripts/save/save_codec.gd
class_name SaveCodec
extends RefCounted


static func encode(snapshot: SaveSnapshot) -> String:
    if snapshot == null:
        return ""
    return JSON.stringify(snapshot.to_dictionary(), "  ", false)


static func decode(text: String, expected_slot: int) -> SaveSnapshot:
    if expected_slot < 1 or expected_slot > 3:
        return null
    var json := JSON.new()
    if json.parse(text) != OK:
        return null
    if not json.data is Dictionary:
        return null
    var snapshot := SaveSnapshot.from_dictionary(json.data)
    if snapshot == null or snapshot.slot != expected_slot:
        return null
    return snapshot
```

- [ ] **Step 4: Run test to verify it passes**

Run: `& 'D:\Godot4\src\godot\bin\godot.windows.editor.x86_64.mono.console.exe' --headless --path . -s res://tests/run_runtime_suite.gd`

Expected: PASS with exit code 0.

- [ ] **Step 5: Commit**

```bash
git add scripts/save/save_snapshot.gd scripts/save/save_codec.gd tests/save/test_save_codec.gd tests/runtime_suite.gd tests/run_runtime_suite.gd
git commit -m "feat: add lightweight save codec"
```

### Task 2: Save Storage, Manager, and Settings

**Files:**
- Create: `scripts/save/save_storage.gd`
- Create: `scripts/save/save_manager.gd`
- Create: `scripts/save/global_settings_store.gd`
- Create: `scripts/save/global_settings_manager.gd`
- Create: `tests/save/test_save_storage.gd`
- Modify: `tests/runtime_suite.gd`
- Modify: `project.godot`

**Interfaces:**
- Consumes: `SaveSnapshot`, `SaveCodec`
- Produces: `SaveStorage.new(root_path: String = "user://saves")`
- Produces: `SaveStorage.write_slot(snapshot: SaveSnapshot) -> bool`
- Produces: `SaveStorage.read_slot(slot: int) -> SaveSnapshot`
- Produces: `SaveStorage.delete_slot(slot: int) -> bool`
- Produces: `SaveManager.start_or_continue(slot: int = 1) -> SaveSnapshot`
- Produces: `SaveManager.commit(snapshot: SaveSnapshot = null) -> bool`
- Produces: `SaveManager.mark_cell_explored(cell_id: String) -> bool`
- Produces: `SaveManager.has_explored_cell(cell_id: String) -> bool`
- Produces: `SaveManager.get_explored_cells() -> Array[String]`
- Produces: `SaveManager.queue_commit(delay_seconds: float = 0.35) -> void`

- [ ] **Step 1: Write the failing storage test**

```gdscript
# tests/save/test_save_storage.gd
extends Node

const SAVE_SNAPSHOT := preload("res://scripts/save/save_snapshot.gd")
const SAVE_STORAGE := preload("res://scripts/save/save_storage.gd")

const TEST_ROOT := "user://wellwell_storage_test"


func run() -> Array[String]:
    var failures: Array[String] = []
    _clear()
    _assert_write_and_read_slot(failures)
    _clear()
    _assert_backup_is_used_when_primary_is_invalid(failures)
    _clear()
    return failures


func _assert_write_and_read_slot(failures: Array[String]) -> void:
    var storage := SAVE_STORAGE.new(TEST_ROOT)
    var snapshot := SAVE_SNAPSHOT.new()
    snapshot.slot = 1
    snapshot.respawn_position = Vector2(16, 24)
    snapshot.add_explored_cell("level_01:2,3")

    if not storage.write_slot(snapshot):
        failures.append("write_slot returned false")
        return
    var loaded := storage.read_slot(1)
    if loaded == null:
        failures.append("read_slot returned null")
        return
    if loaded.respawn_position != Vector2(16, 24):
        failures.append("loaded respawn position was wrong")
    if not loaded.has_explored_cell("level_01:2,3"):
        failures.append("loaded explored cell was missing")


func _assert_backup_is_used_when_primary_is_invalid(failures: Array[String]) -> void:
    var storage := SAVE_STORAGE.new(TEST_ROOT)
    var snapshot := SAVE_SNAPSHOT.new()
    snapshot.slot = 1
    snapshot.add_explored_cell("level_01:backup")
    if not storage.write_slot(snapshot):
        failures.append("initial write failed")
        return

    var primary_path := "%s/slot_1.json" % TEST_ROOT
    var backup_path := "%s/slot_1.backup.json" % TEST_ROOT
    DirAccess.rename_absolute(ProjectSettings.globalize_path(primary_path), ProjectSettings.globalize_path(backup_path))
    var file := FileAccess.open(primary_path, FileAccess.WRITE)
    file.store_string("{broken")
    file.close()

    var loaded := storage.read_slot(1)
    if loaded == null or not loaded.has_explored_cell("level_01:backup"):
        failures.append("backup snapshot was not loaded")


func _clear() -> void:
    var storage := SAVE_STORAGE.new(TEST_ROOT)
    storage.delete_slot(1)
    var root := ProjectSettings.globalize_path(TEST_ROOT)
    if DirAccess.dir_exists_absolute(root):
        DirAccess.remove_absolute(root)
```

Modify `tests/runtime_suite.gd`:

```gdscript
const TESTS: Array[Script] = [
    preload("res://tests/save/test_save_codec.gd"),
    preload("res://tests/save/test_save_storage.gd"),
]
```

- [ ] **Step 2: Run test to verify it fails**

Run: `& 'D:\Godot4\src\godot\bin\godot.windows.editor.x86_64.mono.console.exe' --headless --path . -s res://tests/run_runtime_suite.gd`

Expected: FAIL because `SaveStorage` does not exist.

- [ ] **Step 3: Implement storage, manager, settings, and autoloads**

Implement `SaveStorage` using `after-blast`'s primary/tmp/backup rename pattern. Implement `SaveManager` as an autoload with a one-shot `Timer` child for debounced commits. Implement `GlobalSettingsStore` as merge-preserving JSON persistence and `GlobalSettingsManager` with validated defaults.

Add this section to `project.godot` if it does not exist:

```ini
[autoload]

SaveManager="*res://scripts/save/save_manager.gd"
GlobalSettings="*res://scripts/save/global_settings_manager.gd"
```

- [ ] **Step 4: Run test to verify it passes**

Run: `& 'D:\Godot4\src\godot\bin\godot.windows.editor.x86_64.mono.console.exe' --headless --path . -s res://tests/run_runtime_suite.gd`

Expected: PASS with exit code 0.

- [ ] **Step 5: Commit**

```bash
git add project.godot scripts/save tests/save/test_save_storage.gd tests/runtime_suite.gd
git commit -m "feat: add save storage and settings"
```

### Task 3: Fog Visibility Logic

**Files:**
- Create: `scripts/world/fog_visibility.gd`
- Create: `tests/world/test_fog_visibility.gd`
- Modify: `tests/runtime_suite.gd`

**Interfaces:**
- Produces: `static FogVisibility.get_line_cells(from_cell: Vector2i, to_cell: Vector2i) -> Array[Vector2i]`
- Produces: `static FogVisibility.has_line_of_sight(from_cell: Vector2i, to_cell: Vector2i, blockers: Dictionary[Vector2i, bool]) -> bool`
- Produces: `static FogVisibility.compute_visible_cells(origin: Vector2i, radius: int, blockers: Dictionary[Vector2i, bool]) -> Dictionary[Vector2i, bool]`

- [ ] **Step 1: Write the failing fog visibility test**

```gdscript
# tests/world/test_fog_visibility.gd
extends Node

const FOG_VISIBILITY := preload("res://scripts/world/fog_visibility.gd")


func run() -> Array[String]:
    var failures: Array[String] = []
    _assert_wall_blocks_behind_it(failures)
    _assert_target_wall_face_is_visible(failures)
    _assert_exploration_can_accumulate(failures)
    return failures


func _assert_wall_blocks_behind_it(failures: Array[String]) -> void:
    var blockers: Dictionary[Vector2i, bool] = {Vector2i(1, 0): true}
    if FOG_VISIBILITY.has_line_of_sight(Vector2i(0, 0), Vector2i(2, 0), blockers):
        failures.append("line of sight passed through a blocker")


func _assert_target_wall_face_is_visible(failures: Array[String]) -> void:
    var blockers: Dictionary[Vector2i, bool] = {Vector2i(1, 0): true}
    if not FOG_VISIBILITY.has_line_of_sight(Vector2i(0, 0), Vector2i(1, 0), blockers):
        failures.append("target blocker face was hidden")


func _assert_exploration_can_accumulate(failures: Array[String]) -> void:
    var blockers: Dictionary[Vector2i, bool] = {Vector2i(1, 0): true}
    var left := FOG_VISIBILITY.compute_visible_cells(Vector2i(0, 0), 3, blockers)
    var right := FOG_VISIBILITY.compute_visible_cells(Vector2i(2, 0), 3, blockers)
    var explored: Dictionary[Vector2i, bool] = {}
    for cell: Vector2i in left.keys():
        explored[cell] = true
    for cell: Vector2i in right.keys():
        explored[cell] = true
    if not explored.has(Vector2i(-1, 0)) or not explored.has(Vector2i(3, 0)):
        failures.append("exploration did not accumulate across viewpoints")
```

Modify `tests/runtime_suite.gd`:

```gdscript
const TESTS: Array[Script] = [
    preload("res://tests/save/test_save_codec.gd"),
    preload("res://tests/save/test_save_storage.gd"),
    preload("res://tests/world/test_fog_visibility.gd"),
]
```

- [ ] **Step 2: Run test to verify it fails**

Run: `& 'D:\Godot4\src\godot\bin\godot.windows.editor.x86_64.mono.console.exe' --headless --path . -s res://tests/run_runtime_suite.gd`

Expected: FAIL because `FogVisibility` does not exist.

- [ ] **Step 3: Implement fog visibility**

```gdscript
# scripts/world/fog_visibility.gd
class_name FogVisibility
extends RefCounted


static func get_line_cells(from_cell: Vector2i, to_cell: Vector2i) -> Array[Vector2i]:
    var cells: Array[Vector2i] = []
    var x0 := from_cell.x
    var y0 := from_cell.y
    var x1 := to_cell.x
    var y1 := to_cell.y
    var dx := absi(x1 - x0)
    var sx := 1 if x0 < x1 else -1
    var dy := -absi(y1 - y0)
    var sy := 1 if y0 < y1 else -1
    var error := dx + dy
    while true:
        cells.append(Vector2i(x0, y0))
        if x0 == x1 and y0 == y1:
            break
        var twice_error := 2 * error
        if twice_error >= dy:
            error += dy
            x0 += sx
        if twice_error <= dx:
            error += dx
            y0 += sy
    return cells


static func has_line_of_sight(
    from_cell: Vector2i,
    to_cell: Vector2i,
    blockers: Dictionary[Vector2i, bool]
) -> bool:
    var cells := get_line_cells(from_cell, to_cell)
    for index: int in range(cells.size()):
        var cell := cells[index]
        if cell == from_cell or cell == to_cell:
            continue
        if blockers.has(cell):
            return false
    return true


static func compute_visible_cells(
    origin: Vector2i,
    radius: int,
    blockers: Dictionary[Vector2i, bool]
) -> Dictionary[Vector2i, bool]:
    var result: Dictionary[Vector2i, bool] = {}
    var radius_squared := radius * radius
    for y: int in range(origin.y - radius, origin.y + radius + 1):
        for x: int in range(origin.x - radius, origin.x + radius + 1):
            var cell := Vector2i(x, y)
            if origin.distance_squared_to(cell) > radius_squared:
                continue
            if has_line_of_sight(origin, cell, blockers):
                result[cell] = true
    return result
```

- [ ] **Step 4: Run test to verify it passes**

Run: `& 'D:\Godot4\src\godot\bin\godot.windows.editor.x86_64.mono.console.exe' --headless --path . -s res://tests/run_runtime_suite.gd`

Expected: PASS with exit code 0.

- [ ] **Step 5: Commit**

```bash
git add scripts/world/fog_visibility.gd tests/world/test_fog_visibility.gd tests/runtime_suite.gd
git commit -m "feat: add fog visibility rules"
```

### Task 4: Fog Controller Runtime

**Files:**
- Create: `scripts/world/fog_of_war.gd`
- Modify: `scenes/game.tscn`
- Modify: `tests/world/test_fog_visibility.gd`

**Interfaces:**
- Consumes: `FogVisibility.compute_visible_cells(origin, radius, blockers)`
- Consumes: `SaveManager.mark_cell_explored(cell_id: String) -> bool`
- Produces: `FogOfWar.world_to_cell(world_position: Vector2) -> Vector2i`
- Produces: `FogOfWar.cell_to_id(cell: Vector2i) -> String`
- Produces: `FogOfWar.load_explored_cells(cell_ids: Array[String]) -> void`
- Produces: `FogOfWar.is_cell_explored(cell: Vector2i) -> bool`
- Produces: `FogOfWar.reveal_from_player() -> void`

- [ ] **Step 1: Write additional failing fog ID tests**

Add to `tests/world/test_fog_visibility.gd`:

```gdscript
func _assert_cell_ids_are_stable(failures: Array[String]) -> void:
    var fog := preload("res://scripts/world/fog_of_war.gd").new()
    fog.level_id = "level_01"
    if fog.cell_to_id(Vector2i(12, -4)) != "level_01:12,-4":
        failures.append("fog cell id format changed")
    fog.load_explored_cells(["level_01:12,-4", "other:1,1", "broken"])
    if not fog.is_cell_explored(Vector2i(12, -4)):
        failures.append("saved fog cell id was not loaded")
    if fog.is_cell_explored(Vector2i(1, 1)):
        failures.append("foreign level cell id was loaded")
```

Call `_assert_cell_ids_are_stable(failures)` from `run()`.

- [ ] **Step 2: Run test to verify it fails**

Run: `& 'D:\Godot4\src\godot\bin\godot.windows.editor.x86_64.mono.console.exe' --headless --path . -s res://tests/run_runtime_suite.gd`

Expected: FAIL because `fog_of_war.gd` does not exist.

- [ ] **Step 3: Implement fog controller**

Implement `FogOfWar` as a `Node2D` that exports `player_path`, `solid_tiles_path`,
`map_origin_cell`, `map_size_cells`, `cell_size`, `reveal_radius_cells`, and
`level_id`. Use `_draw()` to draw black rects only for cells inside the map rect
that are not explored. Use `SolidTiles.get_used_cells()` to build blockers.

Core ID helpers:

```gdscript
func cell_to_id(cell: Vector2i) -> String:
    return "%s:%d,%d" % [level_id, cell.x, cell.y]


func load_explored_cells(cell_ids: Array[String]) -> void:
    for cell_id: String in cell_ids:
        var parsed := _id_to_cell(cell_id)
        if parsed != null:
            _explored_cells[parsed] = true
```

- [ ] **Step 4: Run test to verify it passes**

Run: `& 'D:\Godot4\src\godot\bin\godot.windows.editor.x86_64.mono.console.exe' --headless --path . -s res://tests/run_runtime_suite.gd`

Expected: PASS with exit code 0.

- [ ] **Step 5: Commit**

```bash
git add scripts/world/fog_of_war.gd tests/world/test_fog_visibility.gd
git commit -m "feat: add fog of war controller"
```

### Task 5: TileSet and Two-Room Tilemap Scene

**Files:**
- Create: `resources/tilesets/template_platform_tileset.tres`
- Modify: `scenes/game.tscn`

**Interfaces:**
- Consumes: `FogOfWar.player_path`
- Consumes: `FogOfWar.solid_tiles_path`
- Produces: scene nodes `Level/BackTiles`, `Level/SolidTiles`, `Level/DetailTiles`, and `FogOfWar`

- [ ] **Step 1: Add a scene structure contract test**

Create a runtime test that loads `res://scenes/game.tscn`, instantiates it, and checks:

```gdscript
var world := load("res://scenes/game.tscn").instantiate()
if world.get_node_or_null("Level/BackTiles") == null:
    failures.append("BackTiles missing")
if world.get_node_or_null("Level/SolidTiles") == null:
    failures.append("SolidTiles missing")
if world.get_node_or_null("Level/DetailTiles") == null:
    failures.append("DetailTiles missing")
if world.get_node_or_null("FogOfWar") == null:
    failures.append("FogOfWar missing")
```

Register this test in `tests/runtime_suite.gd`.

- [ ] **Step 2: Run test to verify it fails**

Run: `& 'D:\Godot4\src\godot\bin\godot.windows.editor.x86_64.mono.console.exe' --headless --path . -s res://tests/run_runtime_suite.gd`

Expected: FAIL because the tilemap nodes and `FogOfWar` are not in the scene.

- [ ] **Step 3: Build tileset and update scene**

Use Godot-compatible `.tres` resources for an 8x8 `TileSet` with embedded atlas
data or simple generated textures. Replace the existing graybox platform
`StaticBody2D` nodes with `TileMapLayer` cells:

- Fill room back walls in `BackTiles`.
- Place solid floor, ceiling, side walls, and separator wall in `SolidTiles`.
- Place trim and visual variety in `DetailTiles`.
- Keep `SpawnPoint`, `ResetZone`, `Player`, `PixelCamera2D`, `GridOverlay`, and `TuningHotkeys`.
- Add `FogOfWar` after the camera/player and set:
  - `player_path = NodePath("../Player")`
  - `solid_tiles_path = NodePath("../Level/SolidTiles")`
  - `map_origin_cell = Vector2i(-24, -12)`
  - `map_size_cells = Vector2i(80, 32)`
  - `reveal_radius_cells = 12`
  - `level_id = "level_01"`

- [ ] **Step 4: Run test to verify it passes**

Run: `& 'D:\Godot4\src\godot\bin\godot.windows.editor.x86_64.mono.console.exe' --headless --path . -s res://tests/run_runtime_suite.gd`

Expected: PASS with exit code 0.

- [ ] **Step 5: Commit**

```bash
git add resources/tilesets/template_platform_tileset.tres scenes/game.tscn tests tests/runtime_suite.gd
git commit -m "feat: build tilemap fog test level"
```

### Task 6: End-to-End Godot Verification

**Files:**
- Modify only if verification exposes defects in files from Tasks 1-5.

**Interfaces:**
- Consumes the full scene and autoload setup.
- Produces verified runnable Godot project state.

- [ ] **Step 1: Run headless runtime suite**

Run: `& 'D:\Godot4\src\godot\bin\godot.windows.editor.x86_64.mono.console.exe' --headless --path . -s res://tests/run_runtime_suite.gd`

Expected: PASS with exit code 0.

- [ ] **Step 2: Run main scene headless smoke test**

Run: `& 'D:\Godot4\src\godot\bin\godot.windows.editor.x86_64.mono.console.exe' --headless --path . --quit-after 2`

Expected: exit code 0 without scene load errors, script parse errors, missing autoload errors, or TileSet resource errors.

- [ ] **Step 3: Inspect changed files**

Run: `git -c safe.directory=D:/Godot4/GodotProject/wellwell diff --stat`

Expected: changes are limited to the planned save, fog, tilemap, test, and project files plus any pre-existing project edits that were intentionally incorporated.

- [ ] **Step 4: Commit fixes if needed**

If verification required fixes after Task 5, stage only the relevant planned
files:

```bash
git add project.godot resources/tilesets/template_platform_tileset.tres scenes/game.tscn scripts/save scripts/world/fog_visibility.gd scripts/world/fog_of_war.gd tests
git commit -m "fix: stabilize tilemap fog runtime"
```

- [ ] **Step 5: Report**

Report the test commands, exit codes, key changed files, and any known manual verification gaps.
