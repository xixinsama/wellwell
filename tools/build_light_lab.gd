extends SceneTree

## Builds the lighting demo room: a swinging lamp over a slab, a second lamp over
## a pool, a "glow through walls" light, and fireflies that are only a few glowing
## pixels each. Everything in it is either an occluder or a light source, so the
## light map shows circles that are cut by the walls.
##
## Run:
##   godot --headless --path . -s res://tools/build_light_lab.gd

const TEMPLATE := preload("res://scenes/rooms/template/level_template.tscn")
const ROOM_BAKER := preload("res://addons/world_editor/authoring/room/room_baker.gd")
const WATER_GRID_SCRIPT: Script = preload("res://addons/fluid_kit/runtime/water/water_grid.gd")
const LIGHT_FIELD_SCRIPT: Script = preload("res://scripts/world/light_field.gd")

const SOURCE_PATH := "res://scenes/levels/test_world/light_lab.tscn"
const ROOM_ID := "light_lab"
const ROOM_RESOURCE_PATH := "res://resources/rooms/generated/light_lab.tres"
const WORLD_PATH := "res://resources/worlds/test_world.tres"
const ROOM_PLACEMENT := preload("res://addons/platformer_kit/world/data/world_room_placement_data.gd")
## Free chunk of the test world next to the existing demo rooms.
const ORIGIN_CHUNK := Vector2i(3, 0)
## Rewriting the source scene throws away hand edits made in the editor, so it is
## opt-in: with this false the tool only re-bakes whatever scene is on disk.
const FORCE_REWRITE := false
const WIDTH_CELLS := 40
const HEIGHT_CELLS := 23
const TILE := 8

const ATLAS_BACKGROUND := Vector2i(0, 5)
const ATLAS_SOLID := Vector2i(1, 0)
## Glass: solid, but light (and sight) pass through it.
const ATLAS_GLASS := Vector2i(0, 3)

## The slab the swinging lamp hangs over: its shadow sweeps across the floor.
const SLAB_LEFT := 13
const SLAB_RIGHT := 23
const SLAB_TOP := 8
const SLAB_BOTTOM := 9
## A pillar and a second wall, so several circles are cut at once.
const PILLAR_LEFT := 8
const PILLAR_RIGHT := 9
const PILLAR_TOP := 13
const PILLAR_BOTTOM := 16
const WALL_COLUMN := 27
const WALL_TOP := 10
const WALL_BOTTOM := 14
## Pool on the right: floor, then water filling the pit above it.
const POOL_LEFT := 30
const POOL_RIGHT := 38
const POOL_FLOOR_ROW := 19
const WATER_TOP_ROW := 15
const WATER_BOTTOM_ROW := 18


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var level_root := TEMPLATE.instantiate()
	level_root.set("room_id", ROOM_ID)
	level_root.set("display_name", "光照实验")
	level_root.set("room_size_chunks", Vector2i.ONE)
	level_root.set("preview_spawn_id", "start")
	level_root.set("map_color", Color(0.95, 0.82, 0.42))
	_paint_terrain(level_root)
	_place_entities(level_root)
	_place_preview(level_root)

	if FileAccess.file_exists(SOURCE_PATH) and not FORCE_REWRITE:
		print("source scene exists, keeping the hand edits: %s" % SOURCE_PATH)
		var existing: Node = (load(SOURCE_PATH) as PackedScene).instantiate()
		var bake_only: Dictionary = ROOM_BAKER.new().bake(existing, SOURCE_PATH)
		existing.free()
		if not bake_only.get("ok", false):
			push_error("room bake failed: %s" % str(bake_only.get("errors", [])))
			quit(1)
			return
		print("re-baked from the existing scene: %s" % str(bake_only.get("outputs", {})))
		_register_in_world()
		quit(0)
		return
	var packed := PackedScene.new()
	var pack_error := packed.pack(level_root)
	if pack_error != OK:
		push_error("could not pack the light room: %d" % pack_error)
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
	_register_in_world()
	quit(0)


## Puts the room into the test world so the demo runs through the real pipeline
## (background field, pixel camera, fog, water, light field, bloom, outline)
## instead of a hand-rolled runner scene.
func _register_in_world() -> void:
	var room_data: Resource = ResourceLoader.load(
		ROOM_RESOURCE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE
	)
	if room_data == null:
		push_error("generated room data missing at %s" % ROOM_RESOURCE_PATH)
		return
	var world := load(WORLD_PATH) as WorldData
	if world == null:
		push_error("could not load %s" % WORLD_PATH)
		return
	if world.has_room(ROOM_ID):
		print("room already registered in the world")
		return
	world.rooms.append(room_data)
	var placement: Resource = ROOM_PLACEMENT.new()
	placement.room_id = ROOM_ID
	placement.origin_chunk = ORIGIN_CHUNK
	world.placements.append(placement)
	world.sort_for_serialization()
	var save_error := ResourceSaver.save(world, WORLD_PATH)
	if save_error != OK:
		push_error("could not save the world: %d" % save_error)
		return
	print("registered %s in %s at chunk %s" % [ROOM_ID, WORLD_PATH, str(ORIGIN_CHUNK)])


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
	# Border.
	for y: int in HEIGHT_CELLS:
		solid.set_cell(Vector2i(0, y), 0, ATLAS_SOLID)
		solid.set_cell(Vector2i(WIDTH_CELLS - 1, y), 0, ATLAS_SOLID)
	for x: int in WIDTH_CELLS:
		solid.set_cell(Vector2i(x, 0), 0, ATLAS_SOLID)
		solid.set_cell(Vector2i(x, HEIGHT_CELLS - 1), 0, ATLAS_SOLID)
	# The slab under the swinging lamp.
	_fill_block(solid, SLAB_LEFT, SLAB_RIGHT, SLAB_TOP, SLAB_BOTTOM)
	# A pillar standing in the open floor.
	_fill_block(solid, PILLAR_LEFT, PILLAR_RIGHT, PILLAR_TOP, PILLAR_BOTTOM)
	# A glass wall next to the pool: it blocks the hero but not the light.
	for y: int in range(WALL_TOP, WALL_BOTTOM + 1):
		solid.set_cell(Vector2i(WALL_COLUMN, y), 0, ATLAS_GLASS)
	# Pool floor and its walls.
	_fill_block(solid, POOL_LEFT, POOL_RIGHT, POOL_FLOOR_ROW, HEIGHT_CELLS - 1)
	_fill_block(solid, POOL_LEFT - 1, POOL_LEFT - 1, WATER_TOP_ROW, POOL_FLOOR_ROW - 1)
	_fill_block(solid, POOL_RIGHT, POOL_RIGHT, WATER_TOP_ROW, POOL_FLOOR_ROW - 1)


func _fill_block(solid: TileMapLayer, left: int, right: int, top_row: int, bottom_row: int) -> void:
	for y: int in range(top_row, bottom_row + 1):
		for x: int in range(left, right + 1):
			solid.set_cell(Vector2i(x, y), 0, ATLAS_SOLID)


func _place_entities(level_root: Node) -> void:
	var entities := level_root.get_node("RoomContent/Entities")
	var spawn := entities.get_node_or_null("StartSpawn") as Node2D
	if spawn != null:
		spawn.position = Vector2(3.0 * TILE, 18.0 * TILE)
		spawn.set("spawn_id", "start")

	# The swinging lamp: its shadow sweeps over the floor as it goes.
	var lamp := RoomLight.new()
	lamp.name = "SwingingLamp"
	lamp.position = Vector2(18.0 * TILE, (SLAB_TOP - 3) * TILE)
	lamp.light_id = "swing"
	lamp.radius = 96.0
	lamp.energy = 1.15
	lamp.color = Color(1.0, 0.86, 0.6)
	lamp.swing_pixels = 26.0
	lamp.swing_speed = 0.22
	lamp.flicker = 0.12
	lamp.flicker_speed = 5.0
	_attach(level_root, entities, lamp)

	# Second lamp over the pool, softer and cooler.
	var pool_lamp := RoomLight.new()
	pool_lamp.name = "PoolLamp"
	pool_lamp.position = Vector2((POOL_LEFT + 3) * TILE, (WATER_TOP_ROW - 3) * TILE)
	pool_lamp.light_id = "pool"
	pool_lamp.radius = 72.0
	pool_lamp.energy = 0.95
	pool_lamp.color = Color(0.72, 0.88, 1.0)
	pool_lamp.flicker = 0.08
	_attach(level_root, entities, pool_lamp)

	# A light that ignores walls, to show a circle that is *not* cut.
	var glow := RoomLight.new()
	glow.name = "UnoccludedGlow"
	glow.position = Vector2(6.0 * TILE, 12.0 * TILE)
	glow.light_id = "glow"
	glow.radius = 34.0
	glow.energy = 0.9
	glow.color = Color(1.0, 0.66, 0.5)
	glow.casts_shadows = false
	glow.flicker = 0.25
	glow.flicker_speed = 7.0
	_attach(level_root, entities, glow)

	# Fireflies: four glowing pixels each, so they read as specks with a bloom.
	for index: int in 6:
		var firefly := RoomLight.new()
		firefly.name = "Firefly%d" % index
		firefly.position = Vector2(
			float(5 + (index * 6) % 30) * TILE,
			float(4 + (index * 5) % 12) * TILE
		)
		firefly.light_id = "firefly%d" % index
		firefly.radius = 3.0
		firefly.energy = 2.6
		firefly.color = Color(1.0, 0.95, 0.55)
		firefly.wander_pixels = 22.0
		firefly.wander_speed = 0.12 + 0.03 * float(index)
		firefly.flicker = 0.45
		firefly.flicker_speed = 3.0 + float(index)
		firefly.casts_shadows = false
		_attach(level_root, entities, firefly)

	# The pool: a grid fluid region, so the surface reflects the lights.
	var pool := FluidRegion.new()
	pool.name = "PoolFluid"
	pool.position = Vector2(float(POOL_LEFT + 1) * TILE, float(WATER_TOP_ROW) * TILE)
	pool.size_cells = Vector2i(
		POOL_RIGHT - POOL_LEFT - 1, WATER_BOTTOM_ROW - WATER_TOP_ROW + 1
	)
	pool.region_id = "pool"
	_attach(level_root, entities, pool)

	# Keep the room lit for the fog, so the hero can see the whole demo.
	var zone := FogZone.new()
	zone.name = "LabLight"
	zone.position = Vector2.ZERO
	zone.mode = FogZone.Mode.LIGHT
	zone.size_cells = Vector2i(WIDTH_CELLS, HEIGHT_CELLS)
	zone.zone_id = "light_lab_lit"
	_attach(level_root, entities, zone)


## The editor preview needs the light field and the grid water bound to the room
## to show anything, so they are added here with the room's own data.
func _place_preview(level_root: Node) -> void:
	var preview := level_root.get_node_or_null("PreviewOnly")
	if preview == null:
		return
	if preview.get_node_or_null("LightField") == null:
		var field := Node2D.new()
		field.name = "LightField"
		field.set_script(LIGHT_FIELD_SCRIPT)
		field.set("player_path", NodePath("../Player"))
		preview.add_child(field)
		field.owner = level_root
	if preview.get_node_or_null("WaterGrid") == null:
		var grid := Node2D.new()
		grid.name = "WaterGrid"
		grid.set_script(WATER_GRID_SCRIPT)
		preview.add_child(grid)
		grid.owner = level_root


func _attach(level_root: Node, parent: Node, node: Node) -> void:
	parent.add_child(node)
	node.owner = level_root
