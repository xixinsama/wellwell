# Platformer Foundation Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Resource-backed world, room, and room-connection data with headless validation tests.

**Architecture:** Keep phase 1 data-only. `RoomData` owns authored room bounds and chunk/cell conversion helpers, `RoomConnectionData` describes authored links, `WorldData` indexes rooms and adjacency, and `WorldValidation` reports authoring mistakes before runtime loading exists.

**Tech Stack:** Godot 4.7, GDScript `Resource` classes, existing `tests/runtime_suite.gd` node-based headless tests.

**Spec:** `docs/superpowers/specs/2026-09-04-platformer-template-foundation-design.md`

## Global Constraints

- The template remains game-agnostic and must not encode Dash2Home-specific mechanics.
- A room is a rectangular authored gameplay area with stable `room_id`.
- A chunk is a fixed 320x180 safe-frame area.
- A cell is an 8x8 fog, tile, and fine-grained logic unit.
- A minimum room is one chunk.
- Chunk-to-cell conversion uses ceiling, so 320x180 becomes 40x23 cells.
- Resource-backed data is the source of truth for `WorldData`, `RoomData`, and `RoomConnectionData`.
- First phase editing uses native Godot tools: `.tscn` room scenes and `.tres` Resources.
- Each phase must be independently testable and avoid changing the player movement controller.

---

## File Structure

- Create `scripts/world/room_data.gd`: authored room metadata plus chunk, pixel, and cell bound helpers.
- Create `scripts/world/room_connection_data.gd`: typed room transition metadata for validation and map rendering.
- Create `scripts/world/world_data.gd`: world metadata, room lookup, room ID listing, and adjacency lookup.
- Create `scripts/world/world_validation.gd`: static validation for duplicate IDs, missing paths, invalid sizes, missing start room, bad adjacency, and bad connections.
- Create `tests/world/test_world_data.gd`: room bounds, chunk IDs, lookup, and adjacency behavior.
- Create `tests/world/test_world_validation.gd`: validation failure coverage for authoring mistakes.
- Modify `tests/runtime_suite.gd`: register the new world data and validation tests.

### Task 1: Room Data Resource

**Files:**
- Create: `scripts/world/room_data.gd`
- Create: `tests/world/test_world_data.gd`
- Modify: `tests/runtime_suite.gd`

**Interfaces:**
- Produces: `RoomData.get_chunk_rect() -> Rect2i`
- Produces: `RoomData.get_pixel_rect(chunk_size_pixels: Vector2i = Vector2i(320, 180)) -> Rect2i`
- Produces: `RoomData.get_cell_rect(cell_size: Vector2i = Vector2i(8, 8), chunk_size_pixels: Vector2i = Vector2i(320, 180)) -> Rect2i`
- Produces: `RoomData.get_chunk_ids(world_id: String) -> Array[String]`
- Produces: `RoomData.contains_chunk(chunk: Vector2i) -> bool`

- [ ] **Step 1: Write the failing room data test**

```gdscript
# tests/world/test_world_data.gd
extends Node

const ROOM_DATA: Script = preload("res://scripts/world/room_data.gd")


func run() -> Array[String]:
	var failures: Array[String] = []
	_assert_room_bounds_convert_between_chunks_pixels_and_cells(failures)
	_assert_room_chunk_ids_are_stable_and_sorted(failures)
	_assert_contains_chunk_uses_room_rect(failures)
	return failures


func _assert_room_bounds_convert_between_chunks_pixels_and_cells(failures: Array[String]) -> void:
	var room: Resource = ROOM_DATA.new()
	room.room_origin_chunk = Vector2i(2, 1)
	room.room_size_chunks = Vector2i(3, 2)

	if room.get_chunk_rect() != Rect2i(2, 1, 3, 2):
		failures.append("room chunk rect was wrong")
	if room.get_pixel_rect() != Rect2i(640, 180, 960, 360):
		failures.append("room pixel rect was wrong")
	if room.get_cell_rect() != Rect2i(80, 23, 120, 46):
		failures.append("room cell rect did not use ceiled chunk cell size")


func _assert_room_chunk_ids_are_stable_and_sorted(failures: Array[String]) -> void:
	var room: Resource = ROOM_DATA.new()
	room.room_origin_chunk = Vector2i(2, 1)
	room.room_size_chunks = Vector2i(2, 2)

	var chunk_ids: Array[String] = room.get_chunk_ids("world_01")

	if chunk_ids != [
		"world_01:chunk:2,1",
		"world_01:chunk:3,1",
		"world_01:chunk:2,2",
		"world_01:chunk:3,2",
	]:
		failures.append("room chunk ids were not stable")


func _assert_contains_chunk_uses_room_rect(failures: Array[String]) -> void:
	var room: Resource = ROOM_DATA.new()
	room.room_origin_chunk = Vector2i(-1, 3)
	room.room_size_chunks = Vector2i(2, 1)

	if not room.contains_chunk(Vector2i(-1, 3)):
		failures.append("room did not contain its first chunk")
	if not room.contains_chunk(Vector2i(0, 3)):
		failures.append("room did not contain its last chunk")
	if room.contains_chunk(Vector2i(1, 3)):
		failures.append("room contained a chunk outside its width")
```

Modify `tests/runtime_suite.gd`:

```gdscript
const TESTS: Array[Script] = [
	preload("res://tests/save/test_save_codec.gd"),
	preload("res://tests/save/test_save_storage.gd"),
	preload("res://tests/world/test_fog_visibility.gd"),
	preload("res://tests/world/test_tilemap_scene_contract.gd"),
	preload("res://tests/world/test_world_data.gd"),
]
```

- [ ] **Step 2: Run test to verify it fails**

Run: `& 'D:\Godot4\src\godot\bin\godot.windows.editor.x86_64.mono.console.exe' --headless --path . -s 'res://tests/run_runtime_suite.gd'`

Expected: FAIL because `scripts/world/room_data.gd` does not exist.

- [ ] **Step 3: Implement room data**

```gdscript
# scripts/world/room_data.gd
class_name RoomData
extends Resource

const DEFAULT_CHUNK_SIZE_PIXELS := Vector2i(320, 180)
const DEFAULT_CELL_SIZE := Vector2i(8, 8)

@export var room_id := ""
@export var display_name := ""
@export_file("*.tscn") var scene_path := ""
@export var room_origin_chunk := Vector2i.ZERO
@export var room_size_chunks := Vector2i.ONE
@export var adjacent_room_ids := PackedStringArray()
@export var map_color := Color.WHITE


static func get_chunk_size_cells(
	cell_size: Vector2i = DEFAULT_CELL_SIZE,
	chunk_size_pixels: Vector2i = DEFAULT_CHUNK_SIZE_PIXELS
) -> Vector2i:
	return Vector2i(
		ceili(float(chunk_size_pixels.x) / float(cell_size.x)),
		ceili(float(chunk_size_pixels.y) / float(cell_size.y))
	)


func get_chunk_rect() -> Rect2i:
	return Rect2i(room_origin_chunk, room_size_chunks)


func get_pixel_rect(chunk_size_pixels: Vector2i = DEFAULT_CHUNK_SIZE_PIXELS) -> Rect2i:
	return Rect2i(room_origin_chunk * chunk_size_pixels, room_size_chunks * chunk_size_pixels)


func get_cell_rect(
	cell_size: Vector2i = DEFAULT_CELL_SIZE,
	chunk_size_pixels: Vector2i = DEFAULT_CHUNK_SIZE_PIXELS
) -> Rect2i:
	var chunk_size_cells := get_chunk_size_cells(cell_size, chunk_size_pixels)
	return Rect2i(room_origin_chunk * chunk_size_cells, room_size_chunks * chunk_size_cells)


func get_chunk_ids(world_id: String) -> Array[String]:
	var result: Array[String] = []
	for y: int in range(room_origin_chunk.y, room_origin_chunk.y + room_size_chunks.y):
		for x: int in range(room_origin_chunk.x, room_origin_chunk.x + room_size_chunks.x):
			result.append("%s:chunk:%d,%d" % [world_id, x, y])
	return result


func contains_chunk(chunk: Vector2i) -> bool:
	return get_chunk_rect().has_point(chunk)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `& 'D:\Godot4\src\godot\bin\godot.windows.editor.x86_64.mono.console.exe' --headless --path . -s 'res://tests/run_runtime_suite.gd'`

Expected: PASS with exit code 0.

- [ ] **Step 5: Commit**

```bash
git add scripts/world/room_data.gd tests/world/test_world_data.gd tests/runtime_suite.gd
git commit -m "feat: add room data resource"
```

### Task 2: World Data and Connections

**Files:**
- Create: `scripts/world/room_connection_data.gd`
- Create: `scripts/world/world_data.gd`
- Modify: `tests/world/test_world_data.gd`

**Interfaces:**
- Consumes: `RoomData.room_id`
- Produces: `RoomConnectionData.Direction` enum values `NONE`, `UP`, `DOWN`, `LEFT`, `RIGHT`
- Produces: exported `RoomConnectionData.from_room_id`, `from_entrance_id`, `to_room_id`, `to_spawn_id`, `direction`
- Produces: `WorldData.get_room(room_id: String) -> Resource`
- Produces: `WorldData.has_room(room_id: String) -> bool`
- Produces: `WorldData.get_room_ids() -> Array[String]`
- Produces: `WorldData.get_adjacent_room_ids(room_id: String) -> Array[String]`

- [ ] **Step 1: Extend the failing world data test**

Append to `tests/world/test_world_data.gd`:

```gdscript
const WORLD_DATA: Script = preload("res://scripts/world/world_data.gd")
const ROOM_CONNECTION_DATA: Script = preload("res://scripts/world/room_connection_data.gd")
```

Update `run()`:

```gdscript
func run() -> Array[String]:
	var failures: Array[String] = []
	_assert_room_bounds_convert_between_chunks_pixels_and_cells(failures)
	_assert_room_chunk_ids_are_stable_and_sorted(failures)
	_assert_contains_chunk_uses_room_rect(failures)
	_assert_world_indexes_rooms_by_id(failures)
	_assert_world_combines_room_and_connection_adjacency(failures)
	return failures
```

Add:

```gdscript
func _assert_world_indexes_rooms_by_id(failures: Array[String]) -> void:
	var room_a: Resource = _make_room("room_a")
	var room_b: Resource = _make_room("room_b")
	var world: Resource = WORLD_DATA.new()
	world.world_id = "world_01"
	world.rooms.assign([room_b, room_a])

	if not world.has_room("room_a"):
		failures.append("world did not find an existing room")
	if world.has_room("missing"):
		failures.append("world found a missing room")
	if world.get_room("room_b") != room_b:
		failures.append("world returned the wrong room")
	if world.get_room_ids() != ["room_a", "room_b"]:
		failures.append("world room ids were not sorted")


func _assert_world_combines_room_and_connection_adjacency(failures: Array[String]) -> void:
	var room_a: Resource = _make_room("room_a")
	room_a.adjacent_room_ids = PackedStringArray(["room_b"])
	var room_b: Resource = _make_room("room_b")
	var room_c: Resource = _make_room("room_c")
	var connection: Resource = ROOM_CONNECTION_DATA.new()
	connection.from_room_id = "room_a"
	connection.from_entrance_id = "exit_right"
	connection.to_room_id = "room_c"
	connection.to_spawn_id = "spawn_left"
	connection.direction = ROOM_CONNECTION_DATA.Direction.RIGHT
	var reverse_connection: Resource = ROOM_CONNECTION_DATA.new()
	reverse_connection.from_room_id = "room_b"
	reverse_connection.from_entrance_id = "exit_left"
	reverse_connection.to_room_id = "room_a"
	reverse_connection.to_spawn_id = "spawn_right"
	reverse_connection.direction = ROOM_CONNECTION_DATA.Direction.LEFT
	var world: Resource = WORLD_DATA.new()
	world.rooms.assign([room_a, room_b, room_c])
	world.connections.assign([connection, reverse_connection])

	if world.get_adjacent_room_ids("room_a") != ["room_b", "room_c"]:
		failures.append("world adjacency did not combine room ids and connections")


func _make_room(room_id: String) -> Resource:
	var room: Resource = ROOM_DATA.new()
	room.room_id = room_id
	room.scene_path = "res://scenes/rooms/%s.tscn" % room_id
	return room
```

- [ ] **Step 2: Run test to verify it fails**

Run: `& 'D:\Godot4\src\godot\bin\godot.windows.editor.x86_64.mono.console.exe' --headless --path . -s 'res://tests/run_runtime_suite.gd'`

Expected: FAIL because `scripts/world/world_data.gd` and `scripts/world/room_connection_data.gd` do not exist.

- [ ] **Step 3: Implement world data and connection data**

```gdscript
# scripts/world/room_connection_data.gd
class_name RoomConnectionData
extends Resource

enum Direction {
	NONE,
	UP,
	DOWN,
	LEFT,
	RIGHT,
}

@export var from_room_id := ""
@export var from_entrance_id := ""
@export var to_room_id := ""
@export var to_spawn_id := ""
@export var direction := Direction.NONE
```

```gdscript
# scripts/world/world_data.gd
class_name WorldData
extends Resource

@export var world_id := ""
@export var start_room_id := ""
@export var start_spawn_id := ""
@export var rooms: Array[Resource] = []
@export var connections: Array[Resource] = []
@export var tags: PackedStringArray = []


func get_room(room_id: String) -> Resource:
	for room: Resource in rooms:
		if room != null and room.room_id == room_id:
			return room
	return null


func has_room(room_id: String) -> bool:
	return get_room(room_id) != null


func get_room_ids() -> Array[String]:
	var result: Array[String] = []
	for room: Resource in rooms:
		if room != null:
			result.append(room.room_id)
	result.sort()
	return result


func get_adjacent_room_ids(room_id: String) -> Array[String]:
	var unique: Dictionary[String, bool] = {}
	var room: Resource = get_room(room_id)
	if room != null:
		for adjacent_id: String in room.adjacent_room_ids:
			if not adjacent_id.is_empty() and adjacent_id != room_id:
				unique[adjacent_id] = true
	for connection: Resource in connections:
		if connection == null:
			continue
		if connection.from_room_id == room_id and not connection.to_room_id.is_empty():
			unique[connection.to_room_id] = true
		if connection.to_room_id == room_id and not connection.from_room_id.is_empty():
			unique[connection.from_room_id] = true
	var result: Array[String] = []
	result.assign(unique.keys())
	result.sort()
	return result
```

- [ ] **Step 4: Run test to verify it passes**

Run: `& 'D:\Godot4\src\godot\bin\godot.windows.editor.x86_64.mono.console.exe' --headless --path . -s 'res://tests/run_runtime_suite.gd'`

Expected: PASS with exit code 0.

- [ ] **Step 5: Commit**

```bash
git add scripts/world/room_connection_data.gd scripts/world/world_data.gd tests/world/test_world_data.gd
git commit -m "feat: add world data resource"
```

### Task 3: World Data Validation

**Files:**
- Create: `scripts/world/world_validation.gd`
- Create: `tests/world/test_world_validation.gd`
- Modify: `tests/runtime_suite.gd`

**Interfaces:**
- Consumes: `WorldData`, `RoomData`, `RoomConnectionData`
- Produces: `static WorldValidation.validate_world(world: WorldData) -> Array[String]`

- [ ] **Step 1: Write the failing validation test**

```gdscript
# tests/world/test_world_validation.gd
extends Node

const ROOM_DATA: Script = preload("res://scripts/world/room_data.gd")
const WORLD_DATA: Script = preload("res://scripts/world/world_data.gd")
const ROOM_CONNECTION_DATA: Script = preload("res://scripts/world/room_connection_data.gd")
const WORLD_VALIDATION: Script = preload("res://scripts/world/world_validation.gd")


func run() -> Array[String]:
	var failures: Array[String] = []
	_assert_valid_world_has_no_errors(failures)
	_assert_validation_reports_room_authoring_errors(failures)
	_assert_validation_reports_bad_adjacency_and_connections(failures)
	return failures


func _assert_valid_world_has_no_errors(failures: Array[String]) -> void:
	var room_a: Resource = _make_room("room_a")
	room_a.adjacent_room_ids = PackedStringArray(["room_b"])
	var room_b: Resource = _make_room("room_b")
	var connection: Resource = _make_connection("room_a", "exit_right", "room_b", "spawn_left")
	var world: Resource = _make_world([room_a, room_b], [connection])
	world.start_room_id = "room_a"
	world.start_spawn_id = "spawn_main"

	var errors: Array[String] = WORLD_VALIDATION.validate_world(world)

	if not errors.is_empty():
		failures.append("valid world returned validation errors: %s" % str(errors))


func _assert_validation_reports_room_authoring_errors(failures: Array[String]) -> void:
	var room_a: Resource = _make_room("room_a")
	var duplicate: Resource = _make_room("room_a")
	var missing_path: Resource = _make_room("missing_path")
	missing_path.scene_path = ""
	var invalid_size: Resource = _make_room("invalid_size")
	invalid_size.room_size_chunks = Vector2i(0, 1)
	var world: Resource = _make_world([room_a, duplicate, missing_path, invalid_size], [])
	world.start_room_id = "unknown_start"

	var errors: Array[String] = WORLD_VALIDATION.validate_world(world)

	_assert_has_error(errors, "duplicate room_id: room_a", failures)
	_assert_has_error(errors, "room missing_path has empty scene_path", failures)
	_assert_has_error(errors, "room invalid_size has invalid room_size_chunks: (0, 1)", failures)
	_assert_has_error(errors, "start_room_id does not reference a room: unknown_start", failures)


func _assert_validation_reports_bad_adjacency_and_connections(failures: Array[String]) -> void:
	var room_a: Resource = _make_room("room_a")
	room_a.adjacent_room_ids = PackedStringArray(["room_b", "room_a"])
	var world: Resource = _make_world([room_a], [
		_make_connection("room_a", "", "missing_room", "spawn_left"),
	])
	world.start_room_id = "room_a"

	var errors: Array[String] = WORLD_VALIDATION.validate_world(world)

	_assert_has_error(errors, "room room_a has unknown adjacent_room_id: room_b", failures)
	_assert_has_error(errors, "room room_a cannot list itself as adjacent", failures)
	_assert_has_error(errors, "connection room_a->missing_room has empty from_entrance_id", failures)
	_assert_has_error(errors, "connection room_a->missing_room references unknown to_room_id", failures)


func _make_world(rooms: Array, connections: Array) -> Resource:
	var world: Resource = WORLD_DATA.new()
	world.world_id = "world_01"
	world.rooms.assign(rooms)
	world.connections.assign(connections)
	return world


func _make_room(room_id: String) -> Resource:
	var room: Resource = ROOM_DATA.new()
	room.room_id = room_id
	room.scene_path = "res://scenes/rooms/%s.tscn" % room_id
	room.room_size_chunks = Vector2i.ONE
	return room


func _make_connection(from_room_id: String, from_entrance_id: String, to_room_id: String, to_spawn_id: String) -> Resource:
	var connection: Resource = ROOM_CONNECTION_DATA.new()
	connection.from_room_id = from_room_id
	connection.from_entrance_id = from_entrance_id
	connection.to_room_id = to_room_id
	connection.to_spawn_id = to_spawn_id
	return connection


func _assert_has_error(errors: Array[String], expected: String, failures: Array[String]) -> void:
	if not errors.has(expected):
		failures.append("missing validation error: %s in %s" % [expected, str(errors)])
```

Modify `tests/runtime_suite.gd`:

```gdscript
const TESTS: Array[Script] = [
	preload("res://tests/save/test_save_codec.gd"),
	preload("res://tests/save/test_save_storage.gd"),
	preload("res://tests/world/test_fog_visibility.gd"),
	preload("res://tests/world/test_tilemap_scene_contract.gd"),
	preload("res://tests/world/test_world_data.gd"),
	preload("res://tests/world/test_world_validation.gd"),
]
```

- [ ] **Step 2: Run test to verify it fails**

Run: `& 'D:\Godot4\src\godot\bin\godot.windows.editor.x86_64.mono.console.exe' --headless --path . -s 'res://tests/run_runtime_suite.gd'`

Expected: FAIL because `scripts/world/world_validation.gd` does not exist.

- [ ] **Step 3: Implement world validation**

```gdscript
# scripts/world/world_validation.gd
class_name WorldValidation
extends RefCounted


static func validate_world(world: WorldData) -> Array[String]:
	var errors: Array[String] = []
	if world == null:
		return ["world is null"]
	if world.world_id.is_empty():
		errors.append("world_id is empty")
	if world.rooms.is_empty():
		errors.append("world has no rooms")

	var room_ids: Dictionary[String, bool] = {}
	for room: Resource in world.rooms:
		if room == null:
			errors.append("world has null room")
			continue
		if room.room_id.is_empty():
			errors.append("room has empty room_id")
			continue
		if room_ids.has(room.room_id):
			errors.append("duplicate room_id: %s" % room.room_id)
		room_ids[room.room_id] = true
		if room.scene_path.is_empty():
			errors.append("room %s has empty scene_path" % room.room_id)
		if room.room_size_chunks.x < 1 or room.room_size_chunks.y < 1:
			errors.append("room %s has invalid room_size_chunks: %s" % [room.room_id, str(room.room_size_chunks)])

	if not world.start_room_id.is_empty() and not room_ids.has(world.start_room_id):
		errors.append("start_room_id does not reference a room: %s" % world.start_room_id)

	for room: Resource in world.rooms:
		if room == null or room.room_id.is_empty():
			continue
		for adjacent_id: String in room.adjacent_room_ids:
			if adjacent_id == room.room_id:
				errors.append("room %s cannot list itself as adjacent" % room.room_id)
			elif not room_ids.has(adjacent_id):
				errors.append("room %s has unknown adjacent_room_id: %s" % [room.room_id, adjacent_id])

	for connection: Resource in world.connections:
		if connection == null:
			errors.append("world has null connection")
			continue
		var connection_name := "%s->%s" % [connection.from_room_id, connection.to_room_id]
		if connection.from_room_id.is_empty():
			errors.append("connection has empty from_room_id")
		elif not room_ids.has(connection.from_room_id):
			errors.append("connection %s references unknown from_room_id" % connection_name)
		if connection.to_room_id.is_empty():
			errors.append("connection has empty to_room_id")
		elif not room_ids.has(connection.to_room_id):
			errors.append("connection %s references unknown to_room_id" % connection_name)
		if connection.from_entrance_id.is_empty():
			errors.append("connection %s has empty from_entrance_id" % connection_name)
		if connection.to_spawn_id.is_empty():
			errors.append("connection %s has empty to_spawn_id" % connection_name)

	return errors
```

- [ ] **Step 4: Run test to verify it passes**

Run: `& 'D:\Godot4\src\godot\bin\godot.windows.editor.x86_64.mono.console.exe' --headless --path . -s 'res://tests/run_runtime_suite.gd'`

Expected: PASS with exit code 0.

- [ ] **Step 5: Commit**

```bash
git add scripts/world/world_validation.gd tests/world/test_world_validation.gd tests/runtime_suite.gd
git commit -m "feat: validate world data resources"
```

### Task 4: Phase 1 Verification

**Files:**
- Modify only files from Tasks 1-3 if verification exposes a defect.

**Interfaces:**
- Consumes: `RoomData`, `RoomConnectionData`, `WorldData`, `WorldValidation`, and `tests/runtime_suite.gd`
- Produces: verified phase 1 foundation data state.

- [ ] **Step 1: Run the full runtime suite**

Run: `& 'D:\Godot4\src\godot\bin\godot.windows.editor.x86_64.mono.console.exe' --headless --path . -s 'res://tests/run_runtime_suite.gd'`

Expected: PASS with exit code 0.

- [ ] **Step 2: Inspect changed files**

Run: `git -c safe.directory=D:/Godot4/GodotProject/wellwell diff --stat`

Expected: phase 1 changes are limited to `scripts/world/room_data.gd`, `scripts/world/room_connection_data.gd`, `scripts/world/world_data.gd`, `scripts/world/world_validation.gd`, `tests/world/test_world_data.gd`, `tests/world/test_world_validation.gd`, and `tests/runtime_suite.gd`, plus existing uncommitted files that predated phase 1.

- [ ] **Step 3: Review for forbidden scope creep**

Run: `git -c safe.directory=D:/Godot4/GodotProject/wellwell diff -- scripts/player scripts/save scenes resources`

Expected: no phase 1 edits in player movement, save serialization, scene files, or art resources.

- [ ] **Step 4: Commit verification fixes if needed**

```bash
git add scripts/world/room_data.gd scripts/world/room_connection_data.gd scripts/world/world_data.gd scripts/world/world_validation.gd tests/world/test_world_data.gd tests/world/test_world_validation.gd tests/runtime_suite.gd
git commit -m "fix: stabilize world data foundation"
```

- [ ] **Step 5: Report**

Report the runtime suite command, exit code, changed phase 1 files, and any pre-existing dirty files intentionally left untouched.
