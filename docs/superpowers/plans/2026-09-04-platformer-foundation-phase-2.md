# Platformer Foundation Phase 2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add runtime room loading that keeps the current room and adjacent rooms resident.

**Architecture:** `RoomRuntime` wraps one authored room scene, applies the room's chunk-derived world position, and exposes tile/entity lookup points. `WorldRuntime` owns one `WorldData`, tracks `current_room_id`, creates `RoomRuntime` children for the current plus adjacent rooms, and frees no-longer-needed rooms.

**Tech Stack:** Godot 4.7, GDScript `Node2D`, `PackedScene.instantiate()`, existing Resource data classes, existing `tests/runtime_suite.gd`.

**Spec:** `docs/superpowers/specs/2026-09-04-platformer-template-foundation-design.md`

## Global Constraints

- The template remains game-agnostic and must not encode Dash2Home-specific mechanics.
- Use current room plus adjacent rooms as the first loading model.
- `WorldRuntime` loads one `WorldData`, tracks `current_room_id`, instantiates current and adjacent rooms, and unloads rooms that are neither current nor adjacent.
- `RoomRuntime` instantiates the room scene, applies room world position from `RoomData`, scans child nodes, collects tile layers, and exposes room chunk bounds to fog and map systems.
- The player controller remains independent and must not know about room loading.
- Do not implement entity base, save binding, fog integration, map rendering, tile atlas work, or editor UI in this phase.

---

## File Structure

- Create `scripts/world/room_runtime.gd`: single-room scene wrapper, room position, layer lookup, entity root lookup, room bounds.
- Create `scripts/world/world_runtime.gd`: world room residency controller and room transition API.
- Create `tests/world/test_room_runtime.gd`: generated PackedScene fixture tests for single-room loading.
- Create `tests/world/test_world_runtime.gd`: generated PackedScene fixture tests for current-plus-adjacent loading and unloading.
- Modify `tests/runtime_suite.gd`: register room/world runtime tests.

### Task 1: Room Runtime

**Files:**
- Create: `scripts/world/room_runtime.gd`
- Create: `tests/world/test_room_runtime.gd`
- Modify: `tests/runtime_suite.gd`

**Interfaces:**
- Consumes: `RoomData.get_pixel_rect() -> Rect2i`
- Consumes: `RoomData.get_chunk_rect() -> Rect2i`
- Consumes: `RoomData.get_cell_rect() -> Rect2i`
- Produces: `RoomRuntime.setup_room(room_data: Resource) -> bool`
- Produces: `RoomRuntime.get_room_id() -> String`
- Produces: `RoomRuntime.get_room_data() -> Resource`
- Produces: `RoomRuntime.get_room_instance() -> Node`
- Produces: `RoomRuntime.get_room_chunk_rect() -> Rect2i`
- Produces: `RoomRuntime.get_room_cell_rect() -> Rect2i`
- Produces: `RoomRuntime.get_layer_node(layer_name: String) -> Node`
- Produces: `RoomRuntime.get_entities_root() -> Node`

**Review Fix Constraints:**
- `setup_room()` must reject non-`RoomData` resources without property access errors.
- Failed `setup_room()` calls must leave `_room_data` and `_room_instance` cleared.
- Missing fixture paths must be removed before missing-scene assertions.
- Fixture save helpers must return the `ResourceSaver.save()` error code.

- [ ] **Step 1: Write the failing room runtime test**

```gdscript
# tests/world/test_room_runtime.gd
extends Node

const ROOM_DATA: Script = preload("res://scripts/world/room_data.gd")
const ROOM_RUNTIME: Script = preload("res://scripts/world/room_runtime.gd")

const FIXTURE_PATH := "user://runtime_room_fixture.tscn"


func run() -> Array[String]:
	var failures: Array[String] = []
	_save_room_fixture()
	_assert_room_runtime_instances_scene_and_applies_position(failures)
	_assert_room_runtime_rejects_missing_scene(failures)
	return failures


func _assert_room_runtime_instances_scene_and_applies_position(failures: Array[String]) -> void:
	var data: Resource = ROOM_DATA.new()
	data.room_id = "room_a"
	data.scene_path = FIXTURE_PATH
	data.room_origin_chunk = Vector2i(2, 1)
	data.room_size_chunks = Vector2i(3, 2)
	var runtime: Node2D = ROOM_RUNTIME.new() as Node2D

	if not runtime.setup_room(data):
		failures.append("room runtime did not load a valid room")
	if runtime.get_room_id() != "room_a":
		failures.append("room runtime returned the wrong room id")
	if runtime.position != Vector2(640, 180):
		failures.append("room runtime did not apply chunk-derived world position")
	if runtime.get_room_instance() == null:
		failures.append("room runtime did not keep the room instance")
	if runtime.get_layer_node("SolidTiles") == null:
		failures.append("room runtime did not expose SolidTiles")
	if runtime.get_entities_root() == null:
		failures.append("room runtime did not expose Entities")
	if runtime.get_room_chunk_rect() != Rect2i(2, 1, 3, 2):
		failures.append("room runtime returned the wrong chunk rect")
	if runtime.get_room_cell_rect() != Rect2i(80, 23, 120, 46):
		failures.append("room runtime returned the wrong cell rect")
	runtime.free()


func _assert_room_runtime_rejects_missing_scene(failures: Array[String]) -> void:
	var data: Resource = ROOM_DATA.new()
	data.room_id = "missing"
	data.scene_path = "user://missing_room_runtime_fixture.tscn"
	var runtime: Node2D = ROOM_RUNTIME.new() as Node2D

	if runtime.setup_room(data):
		failures.append("room runtime accepted a missing scene")
	if runtime.get_room_instance() != null:
		failures.append("room runtime kept an instance after failed setup")
	runtime.free()


func _save_room_fixture() -> void:
	var root := Node2D.new()
	root.name = "RoomRoot"
	for child_name: String in ["BackTiles", "SolidTiles", "GlassTiles", "VisionBlockTiles", "DetailTiles", "MarkerTiles", "Entities"]:
		var child := Node2D.new()
		child.name = child_name
		root.add_child(child)
		child.owner = root
	var packed := PackedScene.new()
	packed.pack(root)
	ResourceSaver.save(packed, FIXTURE_PATH)
	root.free()
```

Modify `tests/runtime_suite.gd`:

```gdscript
	preload("res://tests/world/test_room_runtime.gd"),
```

- [ ] **Step 2: Run test to verify it fails**

Run: `& 'D:\Godot4\src\godot\bin\godot.windows.editor.x86_64.mono.console.exe' --headless --path . -s 'res://tests/run_runtime_suite.gd'`

Expected: FAIL because `scripts/world/room_runtime.gd` does not exist.

- [ ] **Step 3: Implement room runtime**

```gdscript
# scripts/world/room_runtime.gd
class_name RoomRuntime
extends Node2D

var _room_data: Resource
var _room_instance: Node


func setup_room(room_data: Resource) -> bool:
	_clear_room_instance()
	_room_data = room_data
	if room_data == null or room_data.scene_path.is_empty():
		return false
	var packed: PackedScene = load(room_data.scene_path) as PackedScene
	if packed == null:
		return false
	_room_instance = packed.instantiate()
	if _room_instance == null:
		return false
	name = room_data.room_id
	position = Vector2(room_data.get_pixel_rect().position)
	add_child(_room_instance)
	return true


func get_room_id() -> String:
	return "" if _room_data == null else _room_data.room_id


func get_room_data() -> Resource:
	return _room_data


func get_room_instance() -> Node:
	return _room_instance


func get_room_chunk_rect() -> Rect2i:
	return Rect2i() if _room_data == null else _room_data.get_chunk_rect()


func get_room_cell_rect() -> Rect2i:
	return Rect2i() if _room_data == null else _room_data.get_cell_rect()


func get_layer_node(layer_name: String) -> Node:
	if _room_instance == null:
		return null
	return _room_instance.get_node_or_null(layer_name)


func get_entities_root() -> Node:
	return get_layer_node("Entities")


func _clear_room_instance() -> void:
	if _room_instance != null:
		_room_instance.free()
	_room_instance = null
```

- [ ] **Step 4: Run test to verify it passes**

Run: `& 'D:\Godot4\src\godot\bin\godot.windows.editor.x86_64.mono.console.exe' --headless --path . -s 'res://tests/run_runtime_suite.gd'`

Expected: PASS with exit code 0.

- [ ] **Step 5: Commit**

```bash
git add scripts/world/room_runtime.gd tests/world/test_room_runtime.gd tests/runtime_suite.gd
git commit -m "feat: add room runtime wrapper"
```

### Task 2: World Runtime

**Files:**
- Create: `scripts/world/world_runtime.gd`
- Create: `tests/world/test_world_runtime.gd`
- Modify: `tests/runtime_suite.gd`

**Interfaces:**
- Consumes: `WorldData.get_room(room_id: String) -> Resource`
- Consumes: `WorldData.get_adjacent_room_ids(room_id: String) -> Array[String]`
- Consumes: `RoomRuntime.setup_room(room_data: Resource) -> bool`
- Produces: `WorldRuntime.setup_world(world_data: Resource) -> bool`
- Produces: `WorldRuntime.set_current_room(room_id: String) -> bool`
- Produces: `WorldRuntime.refresh_loaded_rooms() -> bool`
- Produces: `WorldRuntime.get_current_room_id() -> String`
- Produces: `WorldRuntime.get_loaded_room_ids() -> Array[String]`
- Produces: `WorldRuntime.get_room_runtime(room_id: String) -> Node`

**Review Fix Constraints:**
- `setup_world()` must reject non-`WorldData` resources without property access errors.
- `set_current_room()` must not change `_current_room_id` unless the target room runtime loads successfully.
- `refresh_loaded_rooms()` returns `true` only when the current room has a loaded runtime.
- Tests must cover unloadable current-room rejection and child count after load/unload.

- [ ] **Step 1: Write the failing world runtime test**

```gdscript
# tests/world/test_world_runtime.gd
extends Node

const ROOM_DATA: Script = preload("res://scripts/world/room_data.gd")
const ROOM_CONNECTION_DATA: Script = preload("res://scripts/world/room_connection_data.gd")
const WORLD_DATA: Script = preload("res://scripts/world/world_data.gd")
const WORLD_RUNTIME: Script = preload("res://scripts/world/world_runtime.gd")

const FIXTURE_PATH := "user://world_runtime_room_fixture.tscn"


func run() -> Array[String]:
	var failures: Array[String] = []
	_save_room_fixture()
	_assert_world_runtime_loads_current_and_adjacent_rooms(failures)
	_assert_world_runtime_rejects_unknown_room(failures)
	return failures


func _assert_world_runtime_loads_current_and_adjacent_rooms(failures: Array[String]) -> void:
	var room_a: Resource = _make_room("room_a", Vector2i(0, 0))
	room_a.adjacent_room_ids = PackedStringArray(["room_b"])
	var room_b: Resource = _make_room("room_b", Vector2i(1, 0))
	room_b.adjacent_room_ids = PackedStringArray(["room_a"])
	var room_c: Resource = _make_room("room_c", Vector2i(2, 0))
	var connection: Resource = ROOM_CONNECTION_DATA.new()
	connection.from_room_id = "room_a"
	connection.from_entrance_id = "exit_right"
	connection.to_room_id = "room_c"
	connection.to_spawn_id = "spawn_left"
	var world: Resource = WORLD_DATA.new()
	world.world_id = "world_01"
	world.start_room_id = "room_a"
	world.rooms.assign([room_a, room_b, room_c])
	world.connections.assign([connection])
	var runtime: Node2D = WORLD_RUNTIME.new() as Node2D

	if not runtime.setup_world(world):
		failures.append("world runtime did not accept a valid world")
	if runtime.get_current_room_id() != "room_a":
		failures.append("world runtime did not enter the start room")
	if runtime.get_loaded_room_ids() != ["room_a", "room_b", "room_c"]:
		failures.append("world runtime did not load current plus adjacent rooms")
	if runtime.get_room_runtime("room_b") == null:
		failures.append("world runtime did not expose a loaded adjacent room")
	if not runtime.set_current_room("room_b"):
		failures.append("world runtime did not change to a valid room")
	if runtime.get_loaded_room_ids() != ["room_a", "room_b"]:
		failures.append("world runtime did not unload rooms outside the adjacency set")
	runtime.free()


func _assert_world_runtime_rejects_unknown_room(failures: Array[String]) -> void:
	var room_a: Resource = _make_room("room_a", Vector2i.ZERO)
	var world: Resource = WORLD_DATA.new()
	world.start_room_id = "room_a"
	world.rooms.assign([room_a])
	var runtime: Node2D = WORLD_RUNTIME.new() as Node2D
	runtime.setup_world(world)

	if runtime.set_current_room("missing"):
		failures.append("world runtime accepted an unknown room")
	if runtime.get_current_room_id() != "room_a":
		failures.append("world runtime changed current room after rejecting unknown room")
	runtime.free()


func _make_room(room_id: String, room_origin_chunk: Vector2i) -> Resource:
	var room: Resource = ROOM_DATA.new()
	room.room_id = room_id
	room.scene_path = FIXTURE_PATH
	room.room_origin_chunk = room_origin_chunk
	room.room_size_chunks = Vector2i.ONE
	return room


func _save_room_fixture() -> void:
	var root := Node2D.new()
	root.name = "RoomRoot"
	var entities := Node2D.new()
	entities.name = "Entities"
	root.add_child(entities)
	entities.owner = root
	var packed := PackedScene.new()
	packed.pack(root)
	ResourceSaver.save(packed, FIXTURE_PATH)
	root.free()
```

Modify `tests/runtime_suite.gd`:

```gdscript
	preload("res://tests/world/test_world_runtime.gd"),
```

- [ ] **Step 2: Run test to verify it fails**

Run: `& 'D:\Godot4\src\godot\bin\godot.windows.editor.x86_64.mono.console.exe' --headless --path . -s 'res://tests/run_runtime_suite.gd'`

Expected: FAIL because `scripts/world/world_runtime.gd` does not exist.

- [ ] **Step 3: Implement world runtime**

```gdscript
# scripts/world/world_runtime.gd
class_name WorldRuntime
extends Node2D

signal current_room_changed(room_id: String)
signal room_loaded(room_id: String, room_runtime: Node)
signal room_unloaded(room_id: String)

const ROOM_RUNTIME_SCRIPT: Script = preload("res://scripts/world/room_runtime.gd")

@export var world_data: Resource

var _current_room_id := ""
var _loaded_rooms: Dictionary[String, Node] = {}


func setup_world(data: Resource) -> bool:
	world_data = data
	_current_room_id = ""
	if world_data == null or world_data.start_room_id.is_empty():
		return false
	return set_current_room(world_data.start_room_id)


func set_current_room(room_id: String) -> bool:
	if world_data == null or not world_data.has_room(room_id):
		return false
	var changed := _current_room_id != room_id
	_current_room_id = room_id
	refresh_loaded_rooms()
	if changed:
		current_room_changed.emit(_current_room_id)
	return true


func refresh_loaded_rooms() -> void:
	if world_data == null or _current_room_id.is_empty():
		return
	var target_ids := _get_target_room_ids()
	for room_id: String in _loaded_rooms.keys():
		if not target_ids.has(room_id):
			var room_runtime: Node = _loaded_rooms[room_id]
			_loaded_rooms.erase(room_id)
			if room_runtime != null:
				room_runtime.free()
			room_unloaded.emit(room_id)
	for room_id: String in target_ids:
		if _loaded_rooms.has(room_id):
			continue
		_load_room(room_id)


func get_current_room_id() -> String:
	return _current_room_id


func get_loaded_room_ids() -> Array[String]:
	var result: Array[String] = []
	result.assign(_loaded_rooms.keys())
	result.sort()
	return result


func get_room_runtime(room_id: String) -> Node:
	return _loaded_rooms.get(room_id, null)


func _get_target_room_ids() -> Array[String]:
	var unique: Dictionary[String, bool] = {_current_room_id: true}
	for adjacent_id: String in world_data.get_adjacent_room_ids(_current_room_id):
		unique[adjacent_id] = true
	var result: Array[String] = []
	result.assign(unique.keys())
	result.sort()
	return result


func _load_room(room_id: String) -> bool:
	var room_data: Resource = world_data.get_room(room_id)
	if room_data == null:
		return false
	var room_runtime: Node2D = ROOM_RUNTIME_SCRIPT.new() as Node2D
	if not room_runtime.setup_room(room_data):
		room_runtime.free()
		return false
	add_child(room_runtime)
	_loaded_rooms[room_id] = room_runtime
	room_loaded.emit(room_id, room_runtime)
	return true
```

- [ ] **Step 4: Run test to verify it passes**

Run: `& 'D:\Godot4\src\godot\bin\godot.windows.editor.x86_64.mono.console.exe' --headless --path . -s 'res://tests/run_runtime_suite.gd'`

Expected: PASS with exit code 0.

- [ ] **Step 5: Commit**

```bash
git add scripts/world/world_runtime.gd tests/world/test_world_runtime.gd tests/runtime_suite.gd
git commit -m "feat: add world runtime loading"
```

### Task 3: Phase 2 Verification

**Files:**
- Modify only files from Tasks 1-2 if verification exposes a defect.

**Interfaces:**
- Consumes: `RoomRuntime`, `WorldRuntime`, and `tests/runtime_suite.gd`
- Produces: verified phase 2 runtime loading state.

- [ ] **Step 1: Run the full runtime suite**

Run: `& 'D:\Godot4\src\godot\bin\godot.windows.editor.x86_64.mono.console.exe' --headless --path . -s 'res://tests/run_runtime_suite.gd'`

Expected: PASS with exit code 0.

- [ ] **Step 2: Inspect changed files**

Run: `git -c safe.directory=D:/Godot4/GodotProject/wellwell diff --stat`

Expected: phase 2 changes are limited to `scripts/world/room_runtime.gd`, `scripts/world/world_runtime.gd`, `tests/world/test_room_runtime.gd`, `tests/world/test_world_runtime.gd`, `tests/runtime_suite.gd`, and this plan document.

- [ ] **Step 3: Review for forbidden scope creep**

Run: `git -c safe.directory=D:/Godot4/GodotProject/wellwell diff -- scripts/player scripts/save resources`

Expected: no phase 2 edits in player movement, save serialization, or art resources.

- [ ] **Step 4: Report**

Report the runtime suite command, exit code, changed phase 2 files, and any known manual Godot editor verification gaps.
