extends SceneTree

## Builds the gas field lab: a 2x2 chunk room (640x360) crossed by corridors, where
## holding the left mouse button pours gas out of a `GasBrush`.
##
## WHY this room exists
## Every other room in the project is one screen (320x180), so the camera never
## moves and a gas field anchored to the room is indistinguishable from one anchored
## to the view. This room is two screens wide *and* two tall: scrolling moves the
## camera over a field that is 160x90 cells, which is where the question "is the gas
## a property of the world or of the screen?" actually has a visible answer.
##
## The layout is deliberately open: four quadrants joined by a corridor gap in each
## divider, so a puff painted in one quadrant can be shoved through a gap and
## watched from the far side of a camera scroll. There is no vent and no ambient gas
## on purpose: the only gas in the room is what the brush puts there.
##
##   & godot --headless --path . -s res://scripts/tools/build_gas_field_lab.gd
##   & godot --headless --path . -s res://scripts/tools/build_gas_field_lab.gd -- --force
##
## It writes, in this order:
##   scenes/levels/test/gas_field_lab.tscn             the authored source room
##   scenes/rooms/generated/gas_field_lab/*            the baked runtime + terrain
##   resources/rooms/generated/gas_field_lab.tres      the RoomData
##   resources/worlds/gas_field_lab_world.tres         a one-room world for the runner
## The runner itself (scenes/levels/test/gas_field_lab_runner.tscn) is hand written:
## it is a handful of nodes pointing at the world above.

const ROOT_SCRIPT: Script = preload("res://addons/world_editor/authoring/room/room_authoring_root.gd")
const SPAWN_SCRIPT: Script = preload("res://addons/platformer_kit/world/entities/spawn_point.gd")
const ATMOSPHERE_SCRIPT: Script = preload("res://addons/fluid_kit/runtime/gas/atmosphere.gd")
const GAS_FIELD_SCRIPT: Script = preload("res://addons/fluid_kit/runtime/gas/gas_field.gd")
const GAS_BRUSH_SCRIPT: Script = preload("res://addons/fluid_kit/runtime/gas/gas_brush.gd")
const ROOM_LIGHT_SCRIPT: Script = preload("res://scripts/world/room_light.gd")
const ROOM_BAKER: Script = preload("res://addons/world_editor/authoring/room/room_baker.gd")
const WORLD_DATA_SCRIPT: Script = preload("res://addons/platformer_kit/world/data/world_data.gd")
const PLACEMENT_SCRIPT: Script = preload("res://addons/platformer_kit/world/data/world_room_placement_data.gd")
const TILESET_PATH := "res://resources/tilesets/primordial_tileset.tres"

const SOURCE_PATH := "res://scenes/levels/test/gas_field_lab.tscn"
const WORLD_PATH := "res://resources/worlds/gas_field_lab_world.tres"
const ROOM_PATH := "res://resources/rooms/generated/gas_field_lab.tres"
const ROOM_ID := "gas_field_lab"
const DISPLAY_NAME := "气体场实验室"
const DESCRIPTION := "2x2 房间：四个象限用走廊连通，按住左键在光标处排气，用来观察世界锚定的流体场。"
const CHUNKS := Vector2i(2, 2)
## Columns and rows of tiles: a chunk is 40 tiles wide and 22.5 tall, so two chunks
## are 80 x 45 (360 / 8 rounds up).
const COLUMNS := 80
const ROWS := 45
## Atlas coordinates the shipped rooms already use, so this one is drawn with the
## same tiles instead of guessing at the atlas: (0,5) is the backdrop, (1,0) the wall
## block (probed from the baked light_lab / gas_lab / test_fog_wide terrain scenes).
const BACKDROP := Vector2i(0, 5)
const WALL := Vector2i(1, 0)

var _force := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_force = OS.get_cmdline_user_args().has("--force")
	print("build_gas_field_lab: starting (force=%s)" % _force)
	if FileAccess.file_exists(SOURCE_PATH) and not _force:
		print("build_gas_field_lab: %s already exists (pass --force to rewrite)" % SOURCE_PATH)
		quit(0)
		return
	var room := _build_room()
	print("build_gas_field_lab: packing")
	var packed := PackedScene.new()
	if packed.pack(room) != OK:
		push_error("build_gas_field_lab: could not pack the room")
		room.free()
		quit(1)
		return
	_ensure_directory(SOURCE_PATH)
	if ResourceSaver.save(packed, SOURCE_PATH) != OK:
		push_error("build_gas_field_lab: could not save %s" % SOURCE_PATH)
		room.free()
		quit(1)
		return
	room.free()
	print("build_gas_field_lab: wrote %s (%d x %d tiles)" % [SOURCE_PATH, COLUMNS, ROWS])
	if not _bake():
		quit(1)
		return
	if not _write_world():
		quit(1)
		return
	print("build_gas_field_lab: done")
	quit(0)


func _build_room() -> Node2D:
	var room: Node2D = ROOT_SCRIPT.new()
	room.name = ROOM_ID
	room.set("room_id", ROOM_ID)
	room.set("display_name", DISPLAY_NAME)
	room.set("room_size_chunks", CHUNKS)
	room.set("preview_spawn_id", "start")
	room.set("map_color", Color(0.45, 0.85, 0.95, 1.0))

	var content := _attach(room, Node2D.new(), "RoomContent")
	_attach(content, Node2D.new(), "Background")
	_attach(content, Node2D.new(), "Foreground")
	var terrain := _attach(content, Node2D.new(), "Terrain")
	var tileset := load(TILESET_PATH) as TileSet
	var backdrop := _attach(terrain, TileMapLayer.new(), "BackTiles", tileset) as TileMapLayer
	var solid := _attach(terrain, TileMapLayer.new(), "SolidTiles", tileset) as TileMapLayer
	var detail := _attach(terrain, TileMapLayer.new(), "DetailTiles", tileset) as TileMapLayer
	# Only SolidTiles collides. A fresh TileMapLayer defaults to collision_enabled =
	# true, and leaving that on the two decorative layers is how a room grows an
	# invisible wall the day someone paints a solid-looking tile into the backdrop
	# (the template turns them off; this generator has to do it explicitly).
	backdrop.collision_enabled = false
	detail.collision_enabled = false
	_paint(backdrop, solid)

	var entities := _attach(content, Node2D.new(), "Entities")
	var spawn := _attach(entities, SPAWN_SCRIPT.new(), "StartSpawn") as Marker2D
	spawn.position = Vector2(48.0, 330.0)
	spawn.set("spawn_id", "start")

	var field := _attach(entities, GAS_FIELD_SCRIPT.new(), "GasField") as Node2D
	field.position = Vector2(320.0, 180.0)
	# Painted smoke has to dissolve, or a few minutes of testing turns the room into
	# a solid veil; refill stays off so nothing is added behind the player's back.
	field.set("ambient", Vector3.ZERO)
	field.set("decay", 0.22)
	field.set("diffusion", 0.25)
	field.set("refill", 0.0)

	var brush := _attach(entities, GAS_BRUSH_SCRIPT.new(), "GasBrush") as Node2D
	brush.position = Vector2(320.0, 180.0)

	for spot: Array in [
		[Vector2(96.0, 88.0), "lab_left", 96.0],
		[Vector2(560.0, 272.0), "lab_right", 88.0],
	]:
		var light := _attach(entities, ROOM_LIGHT_SCRIPT.new(), "LabLight_%s" % spot[1]) as Node2D
		light.position = spot[0]
		light.set("light_id", spot[1])
		light.set("radius", spot[2])
		light.set("color", Color(1.0, 0.86, 0.62, 1.0))

	# PreviewOnly only feeds the editor preview; the baker copies RoomContent alone.
	var preview := _attach(room, Node2D.new(), "PreviewOnly")
	_attach(preview, ATMOSPHERE_SCRIPT.new(), "Atmosphere")
	return room


## One solid layer, one backdrop fill. The layout is a 2x2 block of quadrants joined
## by a corridor gap in the vertical divider and one in the horizontal one.
func _paint(backdrop: TileMapLayer, solid: TileMapLayer) -> void:
	for y: int in ROWS:
		for x: int in COLUMNS:
			backdrop.set_cell(Vector2i(x, y), 0, BACKDROP)
			if _is_solid(x, y):
				solid.set_cell(Vector2i(x, y), 0, WALL)


func _is_solid(x: int, y: int) -> bool:
	# Outer wall, two tiles thick, so the camera never scrolls past it.
	if x <= 1 or x >= COLUMNS - 2 or y <= 1 or y >= ROWS - 2:
		return true
	# Vertical divider down the middle, with a corridor gap around the room's centre.
	if x >= 38 and x <= 39 and (y < 19 or y > 25):
		return true
	# Horizontal divider, with a corridor gap on each side of the vertical one.
	if y >= 20 and y <= 21 and (x < 38 or x > 39):
		return not ((x >= 8 and x <= 14) or (x >= 58 and x <= 64))
	# Two ledges to stand on and two pillars for the flow to wrap around.
	if y >= 30 and y <= 31 and x >= 4 and x <= 20:
		return true
	if y >= 12 and y <= 13 and x >= 58 and x <= 76:
		return true
	if x >= 24 and x <= 25 and y >= 34 and y <= 36:
		return true
	if x >= 52 and x <= 53 and y >= 8 and y <= 10:
		return true
	return false


func _bake() -> bool:
	var packed := load(SOURCE_PATH) as PackedScene
	if packed == null:
		push_error("build_gas_field_lab: could not reload %s" % SOURCE_PATH)
		return false
	var source := packed.instantiate()
	var result: Dictionary = ROOM_BAKER.new().bake(source, SOURCE_PATH)
	source.free()
	if not result.get("ok", false):
		push_error("build_gas_field_lab: bake failed: %s" % str(result.get("errors", [])))
		return false
	print("build_gas_field_lab: baked %s" % str(result.get("outputs", {})))
	return true


## A one-room world keeps this lab out of the shared test world: nothing else can be
## reached from here, so a test never loses its gas to a room hand-over.
func _write_world() -> bool:
	var room_data := load(ROOM_PATH) as Resource
	if room_data == null:
		push_error("build_gas_field_lab: the bake did not produce a RoomData")
		return false
	var world: Resource = WORLD_DATA_SCRIPT.new()
	world.set("world_id", ROOM_ID)
	world.set("display_name", DISPLAY_NAME)
	world.set("description", DESCRIPTION)
	world.set("start_room_id", ROOM_ID)
	world.set("start_spawn_id", "start")
	world.set("rooms", [room_data] as Array[Resource])
	var placement: Resource = PLACEMENT_SCRIPT.new()
	placement.set("room_id", ROOM_ID)
	placement.set("origin_chunk", Vector2i.ZERO)
	world.set("placements", [placement] as Array[Resource])
	_ensure_directory(WORLD_PATH)
	if ResourceSaver.save(world, WORLD_PATH) != OK:
		push_error("build_gas_field_lab: could not save %s" % WORLD_PATH)
		return false
	print("build_gas_field_lab: wrote %s" % WORLD_PATH)
	return true


## Attaches `node` under `parent` with `parent`'s owner, which is what
## `PackedScene.pack` needs for every descendant of the room root.
func _attach(parent: Node, node: Node, node_name: String, tileset: TileSet = null) -> Node:
	node.name = node_name
	if node is TileMapLayer and tileset != null:
		(node as TileMapLayer).tile_set = tileset
	parent.add_child(node)
	node.owner = parent.owner if parent.owner != null else _root_of(parent)
	return node


func _root_of(node: Node) -> Node:
	var current := node
	while current.get_parent() != null:
		current = current.get_parent()
	return current


func _ensure_directory(path: String) -> void:
	var directory := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(directory):
		DirAccess.make_dir_recursive_absolute(directory)
