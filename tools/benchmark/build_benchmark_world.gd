extends SceneTree
## Bake the benchmark rooms into a real world.
##
## `tools/benchmark/benchmark_rooms.gd` is the only source of truth: this script
## turns its rectangles into TileMapLayer cells (through the engine API, never by
## hand-crafting tile data), calls the ladder prefab for ladder rectangles, and
## writes the room, world and terrain resources the world runtime expects.
##
##   godot --headless --path . -s res://tools/benchmark/build_benchmark_world.gd

const ROOMS = preload("res://tools/benchmark/benchmark_rooms.gd")
const TILESET = preload("res://resources/tilesets/primordial_tileset.tres")
## Loaded lazily: preloading the packed ladder zone at parse time allocates Area2D
## RIDs in every process that merely *loads* this script (including the test
## suite's script-highlighting scan), which then leak at exit.
const LADDER_ZONE_PATH := "res://addons/platformer_kit/world/entities/ladder_zone.tscn"
## Room spawns are resolved by script, not by node name.
const SPAWN_POINT_SCRIPT = preload("res://addons/platformer_kit/world/entities/spawn_point.gd")
const WORLD_DATA = preload("res://addons/platformer_kit/world/data/world_data.gd")
const ROOM_DATA = preload("res://addons/platformer_kit/world/data/room_data.gd")
const PLACEMENT = preload("res://addons/platformer_kit/world/data/world_room_placement_data.gd")

const WORLD_ID := "benchmark_world"
const SOLID_ATLAS := Vector2i(0, 0)
const ONE_WAY_ATLAS := Vector2i(0, 4)
const CELL := 8
const LAYERS: Array[String] = [
	"BackTiles",
	"SolidTiles",
	"DetailTiles",
	"GlassTiles",
	"VisionBlockTiles",
	"MarkerTiles",
	"CrumbleTiles",
	"CrumbleOneWayTiles",
]


func _init() -> void:
	var specs := ROOMS.specs()
	DirAccess.make_dir_recursive_absolute("res://scenes/worlds/%s" % WORLD_ID)
	var terrain_root := _terrain_root()
	var solid_layer: TileMapLayer = terrain_root.get_node("Terrain/SolidTiles")
	var room_resources: Array[Resource] = []
	var placements: Array[Resource] = []
	var index := 0
	for spec: Dictionary in specs:
		var room_id := "bench_%02d_%s" % [index, String(spec.id)]
		var origin_chunk := Vector2i(index, 0)
		var origin_cell := origin_chunk * Vector2i(ROOMS.WIDTH, ROOMS.HEIGHT)
		_paint_room(solid_layer, origin_cell, ROOMS.render(spec))
		_add_ladders(terrain_root, origin_cell, spec.get("ladder", []))
		var room_scene_path := _write_room_scene(room_id, spec, origin_cell)
		var terrain_room_path := _write_room_terrain(room_id, spec)
		room_resources.append(_room_data(room_id, room_scene_path, terrain_room_path))
		var placement := PLACEMENT.new() as Resource
		placement.set("room_id", room_id)
		placement.set("origin_chunk", origin_chunk)
		placements.append(placement)
		index += 1
	var terrain_path := "res://scenes/worlds/%s/terrain.tscn" % WORLD_ID
	var packed := PackedScene.new()
	if packed.pack(terrain_root) != OK:
		push_error("could not pack the benchmark terrain")
		quit(1)
		return
	if ResourceSaver.save(packed, terrain_path) != OK:
		push_error("could not save %s" % terrain_path)
		quit(1)
		return
	var first_room := String((room_resources[0] as Resource).get("room_id"))
	var world := WORLD_DATA.new() as Resource
	world.set("world_id", WORLD_ID)
	world.set("display_name", "求解基准")
	world.set("description", "16 rooms, one waypoint pair each")
	world.set("start_room_id", first_room)
	world.set("start_spawn_id", "start")
	world.set("rooms", room_resources)
	world.set("placements", placements)
	world.set("terrain_scene_path", terrain_path)
	var world_path := "res://resources/worlds/%s.tres" % WORLD_ID
	if ResourceSaver.save(world, world_path) != OK:
		push_error("could not save %s" % world_path)
		quit(1)
		return
	print("benchmark world written: %d rooms" % room_resources.size())
	print("  %s" % terrain_path)
	print("  %s" % world_path)
	terrain_root.free()
	quit(0)


func _terrain_root() -> Node2D:
	var built_root := Node2D.new()
	built_root.name = "WorldTerrain"
	# The world terrain runtime requires a Background node beside the Terrain
	# layers, or it rejects the scene and the session refuses to start.
	var background := Node2D.new()
	background.name = "Background"
	built_root.add_child(background)
	background.owner = built_root
	var terrain := Node2D.new()
	terrain.name = "Terrain"
	built_root.add_child(terrain)
	terrain.owner = built_root
	for layer_name: String in LAYERS:
		var layer := TileMapLayer.new()
		layer.name = layer_name
		layer.tile_set = TILESET
		layer.collision_enabled = layer_name == "SolidTiles"
		terrain.add_child(layer)
		layer.owner = built_root
	return built_root


func _paint_room(solid_layer: TileMapLayer, origin_cell: Vector2i, rows: Array[String]) -> void:
	for y: int in range(rows.size()):
		var row: String = rows[y]
		for x: int in range(row.length()):
			var symbol := row[x]
			if symbol == "#":
				solid_layer.set_cell(origin_cell + Vector2i(x, y), 0, SOLID_ATLAS)
			elif symbol == "-":
				solid_layer.set_cell(origin_cell + Vector2i(x, y), 0, ONE_WAY_ATLAS)


func _add_ladders(holder: Node2D, origin_cell: Vector2i, rects: Array) -> void:
	for value: Variant in rects:
		var rect: Rect2i = value
		var ladder_packed: PackedScene = load(LADDER_ZONE_PATH) as PackedScene
		if ladder_packed == null:
			return
		var zone := ladder_packed.instantiate() as Area2D
		var size := Vector2(rect.size) * float(CELL)
		zone.position = Vector2(origin_cell + rect.position) * float(CELL) + size * 0.5
		var shape := zone.get_node_or_null("CollisionShape2D") as CollisionShape2D
		if shape != null:
			var rectangle := RectangleShape2D.new()
			rectangle.size = size
			shape.shape = rectangle
		holder.add_child(zone)
		zone.owner = holder


func _write_room_scene(room_id: String, spec: Dictionary, _origin_cell: Vector2i) -> String:
	var directory := "res://scenes/rooms/generated/%s" % room_id
	DirAccess.make_dir_recursive_absolute(directory)
	var room := Node2D.new()
	room.name = room_id
	# spawn_point.gd extends Marker2D, so the node has to be created from the
	# script itself: set_script() on a plain Node2D is silently refused and the
	# room then has no spawn point at all.
	var spawn: Node2D = SPAWN_POINT_SCRIPT.new()
	spawn.name = "start"
	spawn.set("spawn_id", "start")
	spawn.position = Vector2(spec.start) * float(CELL)
	room.add_child(spawn)
	spawn.owner = room
	var goal: Node2D = SPAWN_POINT_SCRIPT.new()
	goal.name = "goal"
	goal.set("spawn_id", "goal")
	goal.position = Vector2(spec.goal) * float(CELL)
	room.add_child(goal)
	goal.owner = room
	var packed := PackedScene.new()
	if packed.pack(room) != OK:
		push_error("could not pack %s" % room_id)
		return ""
	var path := "%s/runtime.tscn" % directory
	ResourceSaver.save(packed, path)
	room.free()
	return path


## The world runtime loads a terrain scene per room, with cells in room-local
## coordinates; the world-level scene exists for authoring and the editor.
func _write_room_terrain(room_id: String, spec: Dictionary) -> String:
	var directory := "res://scenes/rooms/generated/%s" % room_id
	DirAccess.make_dir_recursive_absolute(directory)
	var room_terrain := _terrain_root()
	var solid_layer: TileMapLayer = room_terrain.get_node("Terrain/SolidTiles")
	_paint_room(solid_layer, Vector2i.ZERO, ROOMS.render(spec))
	_add_ladders(room_terrain, Vector2i.ZERO, spec.get("ladder", []))
	var packed := PackedScene.new()
	if packed.pack(room_terrain) != OK:
		push_error("could not pack terrain for %s" % room_id)
		room_terrain.free()
		return ""
	var path := "%s/terrain.tscn" % directory
	ResourceSaver.save(packed, path)
	room_terrain.free()
	return path


func _room_data(room_id: String, scene_path: String, terrain_path: String) -> Resource:
	var data := ROOM_DATA.new() as Resource
	data.set("room_id", room_id)
	data.set("display_name", room_id)
	data.set("scene_path", scene_path)
	data.set("source_scene_path", scene_path)
	data.set("terrain_scene_path", terrain_path)
	data.set("room_size_chunks", Vector2i(1, 1))
	data.set("spawn_ids", PackedStringArray(["start", "goal"]))
	return data
