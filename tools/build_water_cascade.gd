extends SceneTree

## Builds the three-pool cascade room: a high pool on the left spills into a
## middle pool, which spills into a low pool on the right. Two waterfalls, three
## separate basins, no gates (the cascade starts immediately).
##
## Run:
##   godot --headless --path . -s res://tools/build_water_cascade.gd

const TEMPLATE := preload("res://scenes/rooms/template/level_template.tscn")
const ROOM_BAKER := preload("res://addons/world_editor/authoring/room/room_baker.gd")

const SOURCE_PATH := "res://scenes/levels/test/water_cascade.tscn"
const ROOM_ID := "water_cascade"
const WIDTH_CELLS := 40
const HEIGHT_CELLS := 23
const TILE := 8

const ATLAS_BACKGROUND := Vector2i(0, 5)
const ATLAS_SOLID := Vector2i(1, 0)

## Pool A: high, left. Floor row 7, initial surface row 4.
const A_FLOOR_ROW := 7
const A_SURFACE_ROW := 2
const A_LEFT := 2
const A_RIGHT := 12
## Pool B: middle, floor row 12.
const B_FLOOR_ROW := 12
const B_LEFT := 14
const B_RIGHT := 25
## Pool C: low, right, floor row 19.
const C_FLOOR_ROW := 19
const C_LEFT := 27
const C_RIGHT := 38
## Solid lips between the pools (crest = top row of the wall).
const LIP_A_ROW := 5
const LIP_B_ROW := 11


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var level_root := TEMPLATE.instantiate()
	level_root.set("room_id", ROOM_ID)
	level_root.set("display_name", "三池级联")
	level_root.set("room_size_chunks", Vector2i.ONE)
	level_root.set("preview_spawn_id", "start")
	level_root.set("map_color", Color(0.3, 0.7, 1.0))
	_paint_terrain(level_root)
	_place_entities(level_root)

	var packed := PackedScene.new()
	var pack_error := packed.pack(level_root)
	if pack_error != OK:
		push_error("could not pack the cascade room: %d" % pack_error)
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

	# Basin blocks run all the way down so the column scan finds their top.
	_fill_block(solid, A_LEFT, A_RIGHT, A_FLOOR_ROW, HEIGHT_CELLS - 1)
	_fill_block(solid, B_LEFT, B_RIGHT, B_FLOOR_ROW, HEIGHT_CELLS - 1)
	_fill_block(solid, C_LEFT, C_RIGHT, C_FLOOR_ROW, HEIGHT_CELLS - 1)
	# Lips between the basins.
	_fill_block(solid, A_RIGHT + 1, A_RIGHT + 1, LIP_A_ROW, HEIGHT_CELLS - 1)
	_fill_block(solid, B_RIGHT + 1, B_RIGHT + 1, LIP_B_ROW, HEIGHT_CELLS - 1)


func _fill_block(solid: TileMapLayer, left: int, right: int, top_row: int, bottom_row: int) -> void:
	for y: int in range(top_row, bottom_row + 1):
		for x: int in range(left, right + 1):
			solid.set_cell(Vector2i(x, y), 0, ATLAS_SOLID)


func _place_entities(level_root: Node) -> void:
	var entities := level_root.get_node("RoomContent/Entities")
	var spawn := entities.get_node_or_null("StartSpawn") as Node2D
	if spawn != null:
		spawn.position = Vector2(float(C_LEFT + 2) * TILE, float(C_FLOOR_ROW - 1) * TILE)
		spawn.set("spawn_id", "start")

	# Pool A starts full up to its lip; B and C start dry and fill from the spills.
	var basin := WaterBasin.new()
	basin.name = "WaterBasinA"
	basin.position = Vector2(float(A_LEFT) * TILE, float(A_SURFACE_ROW) * TILE)
	basin.size_cells = Vector2i(A_RIGHT - A_LEFT + 1, A_FLOOR_ROW - A_SURFACE_ROW)
	basin.basin_id = "cascade_a"
	_attach(level_root, entities, basin)

	# B and C are dry at start, but their basin markers define the simulation span
	# and their initial surface (their floor) so the height field covers them.
	var basin_b := WaterBasin.new()
	basin_b.name = "WaterBasinB"
	basin_b.position = Vector2(float(B_LEFT) * TILE, float(B_FLOOR_ROW) * TILE)
	basin_b.size_cells = Vector2i(B_RIGHT - B_LEFT + 1, 1)
	basin_b.basin_id = "cascade_b"
	_attach(level_root, entities, basin_b)

	var basin_c := WaterBasin.new()
	basin_c.name = "WaterBasinC"
	basin_c.position = Vector2(float(C_LEFT) * TILE, float(C_FLOOR_ROW) * TILE)
	basin_c.size_cells = Vector2i(C_RIGHT - C_LEFT + 1, 1)
	basin_c.basin_id = "cascade_c"
	_attach(level_root, entities, basin_c)

	var warm := FogLight.new()
	warm.name = "CascadeLightTop"
	warm.position = Vector2(float(A_LEFT) * TILE + 24.0, float(A_SURFACE_ROW) * TILE - 24.0)
	warm.light_id = "cascade_top"
	warm.radius = 96.0
	warm.energy = 0.9
	warm.color = Color(1.0, 0.9, 0.72)
	_attach(level_root, entities, warm)

	var cool := FogLight.new()
	cool.name = "CascadeLightBottom"
	cool.position = Vector2(float(C_LEFT) * TILE + 40.0, float(C_FLOOR_ROW - 4) * TILE)
	cool.light_id = "cascade_bottom"
	cool.radius = 110.0
	cool.energy = 0.8
	cool.color = Color(0.6, 0.82, 1.0)
	_attach(level_root, entities, cool)

	var hall_light := FogZone.new()
	hall_light.name = "CascadeRoomLight"
	hall_light.position = Vector2.ZERO
	hall_light.mode = FogZone.Mode.LIGHT
	hall_light.size_cells = Vector2i(WIDTH_CELLS, HEIGHT_CELLS)
	hall_light.zone_id = "water_cascade_lit"
	_attach(level_root, entities, hall_light)


func _attach(level_root: Node, parent: Node, node: Node) -> void:
	parent.add_child(node)
	node.owner = level_root
