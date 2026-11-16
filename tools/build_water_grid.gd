extends SceneTree

## Builds the 2D grid fluid demo room: a tall fluid region on a raised basin, a
## dam that it spills over, and a floor with a drain hole underneath.
##
## Run:
##   godot --headless --path . -s res://tools/build_water_grid.gd

const TEMPLATE := preload("res://scenes/rooms/template/level_template.tscn")
const ROOM_BAKER := preload("res://addons/world_editor/authoring/room/room_baker.gd")
const WATER_GRID_SCRIPT: Script = preload("res://addons/fluid_kit/runtime/water/water_grid.gd")

const SOURCE_PATH := "res://scenes/levels/test/water_grid.tscn"
const ROOM_ID := "water_grid"
const WIDTH_CELLS := 40
const HEIGHT_CELLS := 23
const TILE := 8

const ATLAS_BACKGROUND := Vector2i(0, 5)
const ATLAS_SOLID := Vector2i(1, 0)

## Left basin: floor row 14, dam on the right.
const BASIN_FLOOR_ROW := 14
const BASIN_LEFT := 1
const BASIN_RIGHT := 18
const DAM_COLUMN := 19
const DAM_TOP_ROW := 9
## A rock column standing inside the fluid region: the region loses its cells.
const PILLAR_LEFT := 8
const PILLAR_RIGHT := 9
const PILLAR_TOP_ROW := 8
## The fluid region itself: rows 5..13 on the basin, so the top rows are above the
## dam crest and pour over immediately.
const FLUID_TOP_ROW := 5
const FLUID_BOTTOM_ROW := 13
## Right floor with a drain hole.
const RIGHT_FLOOR_ROW := 19
const HOLE_LEFT := 30
const HOLE_RIGHT := 31


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var root := TEMPLATE.instantiate()
	root.set("room_id", ROOM_ID)
	root.set("display_name", "栅格流体")
	root.set("room_size_chunks", Vector2i.ONE)
	root.set("preview_spawn_id", "start")
	root.set("map_color", Color(0.24, 0.62, 0.95))
	_paint_terrain(root)
	_place_entities(root)
	_place_preview(root)

	var packed := PackedScene.new()
	var pack_error := packed.pack(root)
	if pack_error != OK:
		push_error("could not pack the grid room: %d" % pack_error)
		root.free()
		quit(1)
		return
	var save_error := ResourceSaver.save(packed, SOURCE_PATH)
	if save_error != OK:
		push_error("could not save %s: %d" % [SOURCE_PATH, save_error])
		root.free()
		quit(1)
		return
	print("saved source room: %s" % SOURCE_PATH)

	var bake_result: Dictionary = ROOM_BAKER.new().bake(root, SOURCE_PATH)
	root.free()
	if not bake_result.get("ok", false):
		push_error("room bake failed: %s" % str(bake_result.get("errors", [])))
		quit(1)
		return
	print("baked room: %s" % str(bake_result.get("outputs", {})))
	quit(0)


func _paint_terrain(root: Node) -> void:
	var terrain := root.get_node("RoomContent/Terrain")
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
		solid.set_cell(Vector2i(x, HEIGHT_CELLS - 1), 0, ATLAS_SOLID)

	# Left basin floor, running down so the column scan finds its top.
	_fill_block(solid, BASIN_LEFT, BASIN_RIGHT, BASIN_FLOOR_ROW, HEIGHT_CELLS - 1)
	# Dam wall on the right of the basin.
	_fill_block(solid, DAM_COLUMN, DAM_COLUMN, DAM_TOP_ROW, HEIGHT_CELLS - 1)
	# Right floor with a drain hole.
	_fill_block(solid, DAM_COLUMN + 1, WIDTH_CELLS - 2, RIGHT_FLOOR_ROW, HEIGHT_CELLS - 1)
	for y in range(RIGHT_FLOOR_ROW, HEIGHT_CELLS - 1):
		for x in range(HOLE_LEFT, HOLE_RIGHT + 1):
			solid.erase_cell(Vector2i(x, y))
	# Rock column standing in the fluid.
	_fill_block(solid, PILLAR_LEFT, PILLAR_RIGHT, PILLAR_TOP_ROW, BASIN_FLOOR_ROW - 1)


func _fill_block(solid: TileMapLayer, left: int, right: int, top_row: int, bottom_row: int) -> void:
	for y: int in range(top_row, bottom_row + 1):
		for x: int in range(left, right + 1):
			solid.set_cell(Vector2i(x, y), 0, ATLAS_SOLID)


func _place_entities(root: Node) -> void:
	var entities := root.get_node("RoomContent/Entities")
	var spawn := entities.get_node_or_null("StartSpawn") as Node2D
	if spawn != null:
		# Start the hero inside the left pool: the water is deep there, so the
		# splash reads, and the cascade runs into view as the basin spills.
		spawn.position = Vector2(float(BASIN_LEFT + 4) * TILE, float(BASIN_FLOOR_ROW - 2) * TILE)
		spawn.set("spawn_id", "start")

	var region := FluidRegion.new()
	region.name = "FluidRegionBasin"
	region.position = Vector2(float(BASIN_LEFT + 1) * TILE, float(FLUID_TOP_ROW) * TILE)
	region.size_cells = Vector2i(
		BASIN_RIGHT - BASIN_LEFT,
		FLUID_BOTTOM_ROW - FLUID_TOP_ROW + 1
	)
	region.region_id = "basin"
	_attach(root, entities, region)

	var warm := FogLight.new()
	warm.name = "CascadeLightTop"
	warm.position = Vector2(float(DAM_COLUMN) * TILE, float(DAM_TOP_ROW - 3) * TILE)
	warm.light_id = "grid_top"
	warm.radius = 110.0
	warm.energy = 0.9
	warm.color = Color(1.0, 0.9, 0.72)
	_attach(root, entities, warm)

	var cool := FogLight.new()
	cool.name = "CascadeLightBottom"
	cool.position = Vector2(float(HOLE_LEFT) * TILE, float(RIGHT_FLOOR_ROW - 4) * TILE)
	cool.light_id = "grid_bottom"
	cool.radius = 120.0
	cool.energy = 0.8
	cool.color = Color(0.6, 0.82, 1.0)
	_attach(root, entities, cool)

	var room_light := FogZone.new()
	room_light.name = "GridRoomLight"
	room_light.position = Vector2.ZERO
	room_light.mode = FogZone.Mode.LIGHT
	room_light.size_cells = Vector2i(WIDTH_CELLS, HEIGHT_CELLS)
	room_light.zone_id = "water_grid_lit"
	_attach(root, entities, room_light)


## Adds the 2D fluid to the editor preview so the room can be tuned before baking.
func _place_preview(root: Node) -> void:
	var preview := root.get_node_or_null("PreviewOnly")
	if preview == null:
		return
	if preview.get_node_or_null("WaterGrid") != null:
		return
	var grid := Node2D.new()
	grid.name = "WaterGrid"
	grid.set_script(WATER_GRID_SCRIPT)
	preview.add_child(grid)
	grid.owner = root


func _attach(root: Node, parent: Node, node: Node) -> void:
	parent.add_child(node)
	node.owner = root
