# Spike Tile Hazard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development (recommended) or executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make atlas tile `(0,8)` and its three rotated alternatives respawn the player at the last checkpoint when touched, using half-tile trigger areas.

**Architecture:** Add rotated alternatives to the albedo TileSet (no solid collision), add a `SpikeHazardAreaBuilder` under the room template's `Terrain`, and let it generate `Killzone` areas sized to the spike body's half of each painted cell. The existing `Killzone` script already respawns at `spawn_position` and plays the hurt effect.

**Tech Stack:** Godot 4.7, GDScript, TileSet alternatives, TileMapLayer, Area2D, headless runtime suite.

---

### Task 1: Write the failing spike hazard test

**Files:**
- Create: `tests/world/test_spike_hazard.gd`
- Modify: `tests/runtime_suite.gd` (add the preload next to `test_killzone.gd`)

- [ ] **Step 1: Write the test file**

```gdscript
extends Node

## Atlas (0,8) is the spike. Its alternatives rotate it, every spike cell gets a
## half-tile Killzone, and touching one returns the player to `spawn_position`.

const BUILDER_PATH := "res://scripts/world/spike_hazard_area_builder.gd"
const TILESET_PATH := "res://resources/tilesets/primordial_tileset.tres"
const TEMPLATE_PATH := "res://scenes/rooms/template/level_template.tscn"
const ROOM_PATH := "res://scenes/levels/the_world/room_01_00.tscn"
const ROOM_BAKER := preload("res://addons/world_editor/authoring/room/room_baker.gd")
const SPIKE := Vector2i(0, 8)


class FakePlayer:
	extends Node2D
	var spawn_position := Vector2(40, 56)
	var events: Array[String] = []

	func respawn_at(target: Vector2) -> void:
		global_position = target
		events.append("respawn")

	func play_hurt_effect() -> void:
		events.append("hurt:%s" % str(global_position))


func run() -> Array[String]:
	var failures: Array[String] = []
	_assert_tileset(failures)
	_assert_builder_geometry(failures)
	_assert_contact_respawns(failures)
	_assert_template_and_bake(failures)
	return failures


func _assert_tileset(failures: Array[String]) -> void:
	var tile_set := load(TILESET_PATH) as TileSet
	if tile_set == null:
		failures.append("primordial tileset could not be loaded")
		return
	var source := tile_set.get_source(0) as TileSetAtlasSource
	if source == null or not source.has_tile(SPIKE):
		failures.append("the spike tile %s is missing" % SPIKE)
		return
	if source.get_alternative_tiles_count(SPIKE) != 4:
		failures.append("the spike must have four alternatives")
	var expected_flags: Array[Array] = [
		[false, false, false],
		[true, false, true],
		[true, true, false],
		[false, true, true],
	]
	for index: int in 4:
		var alternative_id := source.get_alternative_tile_id(SPIKE, index)
		if alternative_id != index:
			failures.append("spike alternative %d has id %d" % [index, alternative_id])
			continue
		var data := source.get_tile_data(SPIKE, alternative_id)
		if data == null:
			failures.append("spike alternative %d has no TileData" % index)
			continue
		var flags: Array = expected_flags[index]
		if data.flip_h != bool(flags[0]) or data.flip_v != bool(flags[1]) or data.transpose != bool(flags[2]):
			failures.append("spike alternative %d has flags %s/%s/%s" % [
				index, data.flip_h, data.flip_v, data.transpose,
			])
		if data.get_collision_polygons_count(0) != 0:
			failures.append("spike alternative %d must not have solid collision" % index)


func _assert_builder_geometry(failures: Array[String]) -> void:
	var builder := _build_spike_terrain(failures)
	if builder == null:
		return
	if builder.get_child_count() != 4:
		failures.append("expected four spike zones, found %d" % builder.get_child_count())
	var expected := {
		"SpikeZone_0_0": [Vector2(324, 6), Vector2(8, 4)],
		"SpikeZone_1_0": [Vector2(330, 4), Vector2(4, 8)],
		"SpikeZone_2_0": [Vector2(340, 2), Vector2(8, 4)],
		"SpikeZone_3_0": [Vector2(350, 4), Vector2(4, 8)],
	}
	for zone_name: String in expected:
		var zone := builder.get_node_or_null(zone_name) as Area2D
		if zone == null:
			failures.append("missing spike zone %s" % zone_name)
			continue
		var wanted: Array = expected[zone_name]
		if not zone.global_position.is_equal_approx(wanted[0]):
			failures.append("%s is at %s, expected %s" % [zone_name, zone.global_position, wanted[0]])
		var shape := zone.get_node("CollisionShape2D").shape as RectangleShape2D
		if shape == null or not shape.size.is_equal_approx(wanted[1]):
			failures.append("%s has the wrong trigger size" % zone_name)
		if zone.collision_layer != 0 or zone.collision_mask != 2:
			failures.append("%s must only detect collision layer 2" % zone_name)
	builder.get_parent().free()


func _assert_contact_respawns(failures: Array[String]) -> void:
	var builder := _build_spike_terrain(failures)
	if builder == null:
		return
	var zone := builder.get_node_or_null("SpikeZone_0_0") as Area2D
	if zone == null:
		failures.append("no spike zone to test contact")
		builder.get_parent().free()
		return
	var player := FakePlayer.new()
	player.add_to_group("player")
	add_child(player)
	zone.body_entered.emit(player)
	var expected := ["respawn", "hurt:%s" % str(player.spawn_position)]
	if player.events != expected:
		failures.append("spike must respawn before hurt, got %s" % str(player.events))
	var bystander := Node2D.new()
	add_child(bystander)
	zone.body_entered.emit(bystander)
	if player.events.size() != 2:
		failures.append("a non-player body retriggered the spike")
	player.free()
	bystander.free()
	builder.get_parent().free()


func _assert_template_and_bake(failures: Array[String]) -> void:
	var builder_script := load(BUILDER_PATH) as Script
	if builder_script == null:
		failures.append("spike hazard builder is missing")
		return
	var template := load(TEMPLATE_PATH) as PackedScene
	if template == null:
		failures.append("level template could not be loaded")
		return
	var template_root := template.instantiate()
	var template_builder := template_root.get_node_or_null("RoomContent/Terrain/SpikeHazardAreaBuilder")
	if template_builder == null or template_builder.get_script() != builder_script:
		failures.append("level template has no SpikeHazardAreaBuilder")
	template_root.free()
	var room := (load(ROOM_PATH) as PackedScene).instantiate()
	if room.get_node_or_null("RoomContent/Terrain/SpikeHazardAreaBuilder") == null:
		failures.append("room_01_00 did not inherit the spike hazard builder")
	var staged: Dictionary = ROOM_BAKER.new().stage(room, ROOM_PATH)
	if not staged.get("ok", false):
		failures.append("room_01_00 could not stage: %s" % staged.get("errors", []))
	else:
		var terrain := (staged["terrain_scene"] as PackedScene).instantiate()
		var baked_builder := terrain.get_node_or_null("Terrain/SpikeHazardAreaBuilder")
		if baked_builder == null:
			failures.append("baked terrain lost the spike hazard builder")
		elif baked_builder.get_child_count() != 0:
			failures.append("runtime spike zones were serialized into baked terrain")
		terrain.free()
	room.free()


func _build_spike_terrain(failures: Array[String]) -> Node2D:
	var builder_script := load(BUILDER_PATH) as Script
	if builder_script == null:
		failures.append("spike hazard builder is missing")
		return null
	var tiles := load(TILESET_PATH) as TileSet
	if tiles == null:
		failures.append("primordial tileset could not be loaded")
		return null
	var terrain := Node2D.new()
	add_child(terrain)
	terrain.position = Vector2(320, 0)
	var layer := TileMapLayer.new()
	layer.tile_set = tiles
	terrain.add_child(layer)
	for index: int in 4:
		layer.set_cell(Vector2i(index, 0), 0, SPIKE, index)
	var builder := builder_script.new() as Node2D
	terrain.add_child(builder)
	return builder
```

- [ ] **Step 2: Register the test in the suite**

Add this line next to the existing killzone preload in `tests/runtime_suite.gd`:

```gdscript
	preload("res://tests/world/test_spike_hazard.gd"),
```

- [ ] **Step 3: Run the test and confirm it fails**

Run:

```powershell
$godot = "D:\Godot4\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe"
& $godot --headless --path . -s res://tests/run_test_script.gd -- res://tests/world/test_spike_hazard.gd
```

Expected: FAIL with "spike hazard builder is missing" and "the spike must have four alternatives".

### Task 2: Add the rotated spike alternatives and re-bake normals

**Files:**
- Modify: `resources/tilesets/primordial_tileset.tres` (the `0:8/0 = 0` block)
- Regenerate: `resources/tilesets/primordial_tileset_normal.tres`
- Regenerate: `assets/images/primordial_tileset_normal.png`

- [ ] **Step 1: Replace the single spike entry with four alternatives**

Replace the line `0:8/0 = 0` with:

```text
0:8/next_alternative_id = 4
0:8/0 = 0
0:8/1 = 1
0:8/1/flip_h = true
0:8/1/transpose = true
0:8/2 = 2
0:8/2/flip_h = true
0:8/2/flip_v = true
0:8/3 = 3
0:8/3/transpose = true
0:8/3/flip_v = true
```

Do **not** add `physics_layer_0/polygon_*` lines: the spike is trigger-only.

- [ ] **Step 2: Re-bake the normal atlas**

Run:

```powershell
$godot = "D:\Godot4\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe"
& $godot --headless --path . -s res://scripts/tools/bake_tileset_normals.gd
```

Expected: the tool prints the albedo/normal entry counts and exits 0.

- [ ] **Step 3: Run the tileset tests**

Run:

```powershell
& $godot --headless --path . -s res://tests/run_test_script.gd -- res://tests/world/test_tileset_normals.gd
& $godot --headless --path . -s res://tests/run_test_script.gd -- res://tests/world/test_spike_hazard.gd
```

Expected: `test_tileset_normals` passes; `test_spike_hazard` now only fails on the missing builder.

### Task 3: Add the spike hazard builder and template node

**Files:**
- Create: `scripts/world/spike_hazard_area_builder.gd`
- Modify: `scenes/rooms/template/level_template.tscn`

- [ ] **Step 1: Write the builder**

```gdscript
class_name SpikeHazardAreaBuilder
extends Node2D

## Turns painted (0,8) spike cells into half-tile Killzones. The art is authored
## once; the alternatives rotate it with flip_h/flip_v/transpose. The trigger
## covers the half of the cell the spike body occupies (8x4 for floor/ceiling,
## 4x8 for walls) and never becomes solid collision.

const SPIKE_ATLAS := Vector2i(0, 8)
const SOURCE_ID := 0
const BASE_HALF_RECT := Rect2(-4.0, 0.0, 8.0, 4.0)
const KILLZONE_SCENE := preload("res://scenes/world/killzone.tscn")


func _ready() -> void:
	rebuild()


func rebuild() -> int:
	for child: Node in get_children():
		child.free()
	var built := 0
	var terrain := get_parent()
	if terrain == null:
		return built
	for candidate: Node in terrain.get_children():
		var layer := candidate as TileMapLayer
		if layer == null or layer.tile_set == null:
			continue
		var tile_size := Vector2(layer.tile_set.tile_size)
		for cell: Vector2i in layer.get_used_cells():
			if layer.get_cell_source_id(cell) != SOURCE_ID:
				continue
			if layer.get_cell_atlas_coords(cell) != SPIKE_ATLAS:
				continue
			var data := layer.get_cell_tile_data(cell)
			if data == null:
				continue
			var trigger := _trigger_rect(data)
			var zone := KILLZONE_SCENE.instantiate() as Area2D
			zone.name = "SpikeZone_%d_%d" % [cell.x, cell.y]
			var rectangle := RectangleShape2D.new()
			rectangle.size = trigger.size
			(zone.get_node("CollisionShape2D") as CollisionShape2D).shape = rectangle
			add_child(zone)
			var origin := layer.map_to_local(cell) - tile_size * 0.5
			zone.global_position = layer.to_global(origin + trigger.get_center())
			built += 1
	return built


## Mirrors TileData.get_transformed_vertices(): transpose, then flip_h, then
## flip_v. The base spike body is the bottom half of its cell.
func _trigger_rect(data: TileData) -> Rect2:
	var points := PackedVector2Array([
		BASE_HALF_RECT.position,
		Vector2(BASE_HALF_RECT.end.x, BASE_HALF_RECT.position.y),
		BASE_HALF_RECT.end,
		Vector2(BASE_HALF_RECT.position.x, BASE_HALF_RECT.end.y),
	])
	for index: int in points.size():
		var point := points[index]
		if data.transpose:
			point = Vector2(point.y, point.x)
		if data.flip_h:
			point.x = -point.x
		if data.flip_v:
			point.y = -point.y
		points[index] = point
	var bounds := Rect2(points[0], Vector2.ZERO)
	for point: Vector2 in points:
		bounds = bounds.expand(point)
	return bounds
```

- [ ] **Step 2: Add the builder to the room template**

In `scenes/rooms/template/level_template.tscn`, add the script resource next to
the ladder builder resource:

```text
[ext_resource type="Script" path="res://scripts/world/spike_hazard_area_builder.gd" id="13_spike_hazard"]
```

Then add the node immediately after the existing `LadderAreaBuilder` node:

```text
[node name="SpikeHazardAreaBuilder" type="Node2D" parent="RoomContent/Terrain" unique_id=2054308360]
script = ExtResource("13_spike_hazard")
```

- [ ] **Step 3: Check the script and run the spike test**

Run:

```powershell
$godot = "D:\Godot4\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe"
& $godot --headless --path . --check-only -s res://scripts/world/spike_hazard_area_builder.gd
& $godot --headless --path . -s res://tests/run_test_script.gd -- res://tests/world/test_spike_hazard.gd
```

Expected: check-only exits 0; the spike test passes.

- [ ] **Step 4: Run the neighbouring world tests**

Run:

```powershell
& $godot --headless --path . -s res://tests/run_test_script.gd -- res://tests/world/test_killzone.gd
& $godot --headless --path . -s res://tests/run_test_script.gd -- res://tests/world/test_ladder_tiles.gd
& $godot --headless --path . -s res://tests/run_test_script.gd -- res://tests/authoring/test_level_template_contract.gd
```

Expected: all pass.

### Task 4: Document the spike and run the full suite

**Files:**
- Modify: `docs/layers/terrain-tiles.md`
- Modify: `docs/player-effects.md`

- [ ] **Step 1: Update the tile table and consumer table**

In `docs/layers/terrain-tiles.md`:

- Change the "共 23 个图集坐标、56 个图块条目" sentence to 59 条目.
- Remove `(0,8)` from the "无碰撞" row and add a "危险" row:
  `(0,8)` 4 个朝向（朝上/右/下/左），无实体碰撞；每个格子由 `SpikeHazardAreaBuilder` 生成 `8x4`/`4x8` 的 `Killzone` 触发区，接触后回到 `spawn_position`。
- Add a consumer row:
  `SpikeHazardAreaBuilder` | `Terrain` 下所有层，按 `source_id` + `(0,8)` 认尖刺 | 生成半格 `Killzone` | `scripts/world/spike_hazard_area_builder.gd`
- Add a short note that painting a spike requires Sync Terrain and that the
  tile stays non-solid, so light/fog/highlight ignore it and gas/water treat
  the cell as solid like other decoration tiles.

In `docs/player-effects.md`, change the "仅 Killzone 显式请求" line to include
spike hazard zones as a second explicit requester of the hurt effect.

- [ ] **Step 2: Run the full runtime suite**

Run:

```powershell
$godot = "D:\Godot4\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe"
& $godot --headless --path . -s res://tests/run_runtime_suite.gd
```

Expected: exit 0, no failures.

- [ ] **Step 3: Boot the game headlessly and check for warnings**

Run:

```powershell
& $godot --headless --path . --quit-after 2
```

Expected: no `WARNING:` or `ERROR:` lines.

- [ ] **Step 4: Commit**

```powershell
git add resources/tilesets/primordial_tileset.tres resources/tilesets/primordial_tileset_normal.tres assets/images/primordial_tileset_normal.png scripts/world/spike_hazard_area_builder.gd scenes/rooms/template/level_template.tscn tests/world/test_spike_hazard.gd tests/runtime_suite.gd docs/layers/terrain-tiles.md docs/player-effects.md
git commit -m "feat: add spike tile hazards with half-tile respawn triggers"
```
