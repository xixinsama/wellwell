extends SceneTree

## Builds the gas trail room: an empty room (no ambient gas), a GasField marker
## that makes the gas fade out, and a 1x1-cell walker that loops a square path
## and leaves a backward-moving trail.
##
## Run:
##   godot --headless --path . -s res://tools/build_gas_trail.gd

const TEMPLATE := preload("res://scenes/rooms/template/level_template.tscn")
const ROOM_BAKER := preload("res://addons/world_editor/authoring/room/room_baker.gd")

const SOURCE_PATH := "res://scenes/levels/test/gas_trail.tscn"
const ROOM_ID := "gas_trail"
const WIDTH_CELLS := 40
const HEIGHT_CELLS := 23
const TILE := 8

const ATLAS_BACKGROUND := Vector2i(0, 5)
const ATLAS_SOLID := Vector2i(1, 0)

const SQUARE_CENTER := Vector2(160.0, 96.0)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var level_root := TEMPLATE.instantiate()
	level_root.set("room_id", ROOM_ID)
	level_root.set("display_name", "气体尾迹实验室")
	level_root.set("room_size_chunks", Vector2i.ONE)
	level_root.set("preview_spawn_id", "start")
	level_root.set("map_color", Color(0.4, 0.8, 0.95))
	_paint_terrain(level_root)
	_place_entities(level_root)

	var packed := PackedScene.new()
	var pack_error := packed.pack(level_root)
	if pack_error != OK:
		push_error("could not pack the gas trail room: %d" % pack_error)
		level_root.free()
		quit(1)
		return
	var save_error := ResourceSaver.save(packed, SOURCE_PATH)
	if save_error != OK:
		push_error("could not save %s: %d" % [SOURCE_PATH, save_error])
		level_root.free()
		quit(1)
		return
	print("saved source room: %s" % SOURCE_PATH)

	var bake_result: Dictionary = ROOM_BAKER.new().bake(level_root, SOURCE_PATH)
	level_root.free()
	if not bake_result.get("ok", false):
		push_error("room bake failed: %s" % str(bake_result.get("errors", [])))
		quit(1)
		return
	print("baked room: %s" % str(bake_result.get("outputs", {})))
	quit(0)


func _paint_terrain(level_root: Node) -> void:
	var terrain := level_root.get_node("RoomContent/Terrain")
	var back := terrain.get_node("BackTiles") as TileMapLayer
	var solid := terrain.get_node("SolidTiles") as TileMapLayer
	var detail := terrain.get_node("DetailTiles") as TileMapLayer
	back.clear()
	solid.clear()
	detail.clear()

	for y: int in HEIGHT_CELLS:
		for x: int in WIDTH_CELLS:
			back.set_cell(Vector2i(x, y), 0, ATLAS_BACKGROUND)

	for y: int in HEIGHT_CELLS:
		solid.set_cell(Vector2i(0, y), 0, ATLAS_SOLID)
		solid.set_cell(Vector2i(WIDTH_CELLS - 1, y), 0, ATLAS_SOLID)
	for x: int in WIDTH_CELLS:
		solid.set_cell(Vector2i(x, 0), 0, ATLAS_SOLID)
		solid.set_cell(Vector2i(x, HEIGHT_CELLS - 2), 0, ATLAS_SOLID)
		solid.set_cell(Vector2i(x, HEIGHT_CELLS - 1), 0, ATLAS_SOLID)


func _place_entities(level_root: Node) -> void:
	var entities := level_root.get_node("RoomContent/Entities")
	var spawn := entities.get_node_or_null("StartSpawn") as Node2D
	if spawn != null:
		spawn.position = Vector2(40.0, (HEIGHT_CELLS - 2) * TILE)
		spawn.set("spawn_id", "start")

	# No ambient gas, and everything that is emitted fades out over time.
	var field := GasField.new()
	field.name = "GasField"
	field.position = SQUARE_CENTER
	field.ambient = Vector3.ZERO
	field.decay = 0.32
	field.diffusion = 0.25
	field.refill = 0.0
	_attach(level_root, entities, field)

	var walker := GasTrailWalker.new()
	walker.name = "TrailWalker"
	walker.position = SQUARE_CENTER
	walker.square_size = Vector2(150.0, 78.0)
	walker.speed = 70.0
	walker.emit_radius = 13.0
	walker.emit_rate = 6.0
	walker.backward_speed = 105.0
	walker.channel = 1
	_attach(level_root, entities, walker)

	var warm := FogLight.new()
	warm.name = "TrailLightTop"
	warm.position = Vector2(80.0, 48.0)
	warm.light_id = "trail_top"
	warm.radius = 96.0
	warm.energy = 0.9
	warm.color = Color(1.0, 0.9, 0.72)
	_attach(level_root, entities, warm)

	var hall_light := FogZone.new()
	hall_light.name = "TrailRoomLight"
	hall_light.position = Vector2.ZERO
	hall_light.mode = FogZone.Mode.LIGHT
	hall_light.size_cells = Vector2i(WIDTH_CELLS, HEIGHT_CELLS)
	hall_light.zone_id = "gas_trail_lit"
	_attach(level_root, entities, hall_light)


func _attach(level_root: Node, parent: Node, node: Node) -> void:
	parent.add_child(node)
	node.owner = level_root
