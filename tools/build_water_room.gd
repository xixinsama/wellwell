extends SceneTree

## Builds the water hall source room.
##
## Run it once (and again after changing the layout):
##   godot --headless --path . -s res://tools/build_water_room.gd
## It writes the source scene, then bakes it through RoomBaker so the world
## runtime, terrain scene and RoomData resource are regenerated as well.
##
## The layout is one screen (40 x 23 cells of 8 px):
##   - a high tank on the left (floor row 17, water starts at row 11),
##   - a low divider wall (crest row 14) with a sluice gate on top,
##   - a deep basin on the right (floor row 19) that starts empty,
##   - a ledge at the top left to drop from.

const TEMPLATE := preload("res://scenes/rooms/template/level_template.tscn")
const ROOM_BAKER := preload("res://addons/world_editor/authoring/room/room_baker.gd")

const SOURCE_PATH := "res://scenes/levels/test_world/water_hall.tscn"
const ROOM_ID := "water_hall"
const WIDTH_CELLS := 40
const HEIGHT_CELLS := 23
const TILE := 8

const ATLAS_BACKGROUND := Vector2i(0, 5)
const ATLAS_SOLID := Vector2i(1, 0)
const ATLAS_FILL := Vector2i(0, 0)
const ATLAS_DETAIL := Vector2i(1, 5)

# Tank A (left): interior columns 1..15, floor row 17, initial surface row 11.
const TANK_A_LEFT := 1
const TANK_A_RIGHT := 16
const TANK_A_FLOOR_ROW := 17
const TANK_A_SURFACE_ROW := 11
# Divider: columns 16..18, crest row 14.
const DIVIDER_LEFT := 16
const DIVIDER_RIGHT := 19
const DIVIDER_CREST_ROW := 14
# Basin B (right): interior columns 19..38, floor row 19.
const BASIN_B_LEFT := 19
const BASIN_B_RIGHT := 39
const BASIN_B_FLOOR_ROW := 19
# Starting ledge.
const LEDGE_LEFT := 2
const LEDGE_RIGHT := 8
const LEDGE_ROW := 6


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var level_root := TEMPLATE.instantiate()
	level_root.set("room_id", ROOM_ID)
	level_root.set("display_name", "水池与雾气")
	level_root.set("room_size_chunks", Vector2i.ONE)
	level_root.set("preview_spawn_id", "start")
	level_root.set("map_color", Color(0.28, 0.58, 0.86))
	_paint_terrain(level_root)
	_place_entities(level_root)

	var packed := PackedScene.new()
	var pack_error := packed.pack(level_root)
	if pack_error != OK:
		push_error("could not pack the water hall: %d" % pack_error)
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
	for warning: String in bake_result.get("warnings", []):
		print("bake warning: %s" % warning)
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
		_paint_solid(solid, 0, y, ATLAS_SOLID)
		_paint_solid(solid, WIDTH_CELLS - 1, y, ATLAS_SOLID)
	for x: int in WIDTH_CELLS:
		_paint_solid(solid, x, 0, ATLAS_SOLID)
		_paint_solid(solid, x, HEIGHT_CELLS - 2, ATLAS_SOLID)
		_paint_solid(solid, x, HEIGHT_CELLS - 1, ATLAS_SOLID)

	# High tank A: a solid floor with earth underneath and a full-height room wall.
	for x: int in range(TANK_A_LEFT, TANK_A_RIGHT):
		_paint_solid(solid, x, TANK_A_FLOOR_ROW, ATLAS_SOLID)
		for y: int in range(TANK_A_FLOOR_ROW + 1, HEIGHT_CELLS - 2):
			_paint_solid(solid, x, y, ATLAS_FILL)

	# Divider wall: the crest at row 14 makes the spill lip that the gate holds.
	for y: int in range(DIVIDER_CREST_ROW, HEIGHT_CELLS - 2):
		for x: int in range(DIVIDER_LEFT, DIVIDER_RIGHT):
			_paint_solid(solid, x, y, ATLAS_SOLID)

	# Deep basin B: floor row 19, solid underneath.
	for x: int in range(BASIN_B_LEFT, BASIN_B_RIGHT):
		_paint_solid(solid, x, BASIN_B_FLOOR_ROW, ATLAS_SOLID)
		for y: int in range(BASIN_B_FLOOR_ROW + 1, HEIGHT_CELLS - 2):
			_paint_solid(solid, x, y, ATLAS_FILL)

	# Starting ledge.
	for x: int in range(LEDGE_LEFT, LEDGE_RIGHT):
		_paint_solid(solid, x, LEDGE_ROW, ATLAS_SOLID)


func _paint_solid(layer: TileMapLayer, x: int, y: int, atlas: Vector2i) -> void:
	layer.set_cell(Vector2i(x, y), 0, atlas)


func _place_entities(level_root: Node) -> void:
	var entities := level_root.get_node("RoomContent/Entities")
	var spawn := entities.get_node_or_null("StartSpawn") as Node2D
	if spawn != null:
		spawn.position = Vector2(LEDGE_LEFT * TILE + 20.0, LEDGE_ROW * TILE)
		spawn.set("spawn_id", "start")

	var basin_a := WaterBasin.new()
	basin_a.name = "WaterBasinA"
	basin_a.position = Vector2(TANK_A_LEFT * TILE, TANK_A_SURFACE_ROW * TILE)
	basin_a.size_cells = Vector2i(TANK_A_RIGHT - TANK_A_LEFT, TANK_A_FLOOR_ROW - TANK_A_SURFACE_ROW + 1)
	basin_a.basin_id = "tank_a"
	_attach(level_root, entities, basin_a)

	var basin_b := WaterBasin.new()
	basin_b.name = "WaterBasinB"
	basin_b.position = Vector2(BASIN_B_LEFT * TILE, BASIN_B_FLOOR_ROW * TILE)
	basin_b.size_cells = Vector2i(BASIN_B_RIGHT - BASIN_B_LEFT, 2)
	basin_b.basin_id = "basin_b"
	_attach(level_root, entities, basin_b)

	var gate := WaterGate.new()
	gate.name = "SluiceGate"
	gate.position = Vector2(DIVIDER_LEFT * TILE, TANK_A_SURFACE_ROW * TILE)
	gate.size_cells = Vector2i(DIVIDER_RIGHT - DIVIDER_LEFT, 3)
	gate.gate_id = "spill_gate"
	gate.open_delay_seconds = 0.9
	gate.slide_seconds = 0.5
	_attach(level_root, entities, gate)

	var warm := FogLight.new()
	warm.name = "HarborLight"
	warm.position = Vector2(56.0, 56.0)
	warm.light_id = "harbor"
	warm.radius = 84.0
	warm.energy = 1.15
	warm.color = Color(1.0, 0.76, 0.44)
	warm.flicker = 0.16
	_attach(level_root, entities, warm)

	var cool := FogLight.new()
	cool.name = "BasinLight"
	cool.position = Vector2(248.0, 116.0)
	cool.light_id = "basin"
	cool.radius = 96.0
	cool.energy = 0.9
	cool.color = Color(0.52, 0.82, 1.0)
	cool.flicker = 0.08
	cool.flicker_speed = 2.4
	_attach(level_root, entities, cool)

	# The hall is lit as a whole: a LIGHT fog zone covering the room keeps the
	# exploration fog from clipping the pools and the mist into a black band.
	var hall_light := FogZone.new()
	hall_light.name = "HallLight"
	hall_light.position = Vector2.ZERO
	hall_light.mode = FogZone.Mode.LIGHT
	hall_light.size_cells = Vector2i(WIDTH_CELLS, HEIGHT_CELLS)
	hall_light.zone_id = "water_hall_lit"
	_attach(level_root, entities, hall_light)


func _attach(level_root: Node, parent: Node, node: Node) -> void:
	parent.add_child(node)
	node.owner = level_root
