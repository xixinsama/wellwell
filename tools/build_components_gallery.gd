extends SceneTree

## Builds the components gallery: one two-screen room where every platform,
## vision and entity component sits as a self-contained station the author can
## copy into a real room.
##
## Run:
##   godot --headless --path . -s res://tools/build_components_gallery.gd
##
## It writes the source room, bakes it through RoomBaker and registers the baked
## room in the test world at chunk (3, 1). With FORCE_REWRITE off and the source
## scene already on disk, it only re-bakes the existing scene, so hand edits in
## the editor survive.

const TEMPLATE := preload("res://scenes/rooms/template/level_template.tscn")
const ROOM_BAKER := preload("res://addons/world_editor/authoring/room/room_baker.gd")
const PLATFORM_BODY := preload("res://addons/platformer_kit/platforms/platform_body_2d.gd")
const WAYPOINT_MOTION := preload(
	"res://addons/platformer_kit/platforms/components/waypoint_motion_component_2d.gd"
)
const FALL_MOTION := preload(
	"res://addons/platformer_kit/platforms/components/fall_motion_component_2d.gd"
)
const ELEVATOR_MOTION := preload(
	"res://addons/platformer_kit/platforms/components/elevator_motion_component_2d.gd"
)
const CONVEYOR_SURFACE := preload(
	"res://addons/platformer_kit/platforms/components/conveyor_surface_component_2d.gd"
)
const RIDER_TRIGGER := preload(
	"res://addons/platformer_kit/platforms/components/rider_trigger_component_2d.gd"
)
const FOG_OCCLUDER := preload(
	"res://addons/platformer_kit/platforms/components/fog_occluder_component_2d.gd"
)
const DOOR_SCENE := preload("res://scenes/world/fog_door.tscn")
const PHANTOM_WALL_SCENE := preload("res://scenes/world/phantom_wall.tscn")
const ROOM_PLACEMENT := preload("res://addons/platformer_kit/world/data/world_room_placement_data.gd")

const SOURCE_PATH := "res://scenes/levels/test_world/components_gallery.tscn"
const ROOM_ID := "components_gallery"
const ROOM_RESOURCE_PATH := "res://resources/rooms/generated/components_gallery.tres"
const WORLD_PATH := "res://resources/worlds/test_world.tres"
## Two free chunks next to the fog/water rooms: (3, 1) and (4, 1).
const ORIGIN_CHUNK := Vector2i(3, 1)
const FORCE_REWRITE := false

const WIDTH_CELLS := 80
const HEIGHT_CELLS := 23
const TILE := 8
const FLOOR_TOP_ROW := 20
const CEILING_ROW := 0

const ATLAS_BACKGROUND := Vector2i(0, 5)
const ATLAS_SOLID := Vector2i(1, 0)

# --- Station layout (top-left cell of each body, in cells) ---------------------
# 01: rider-triggered lift to a small ledge.
const ELEVATOR_CELL := Vector2i(3, 19)
const ELEVATOR_SIZE := Vector2i(3, 1)
const ELEVATOR_TRAVEL := Vector2(0.0, -48.0)
const ELEVATOR_LEDGE := Rect2i(6, 13, 3, 1)
# 02: conveyor belt on the floor.
const CONVEYOR_CELL := Vector2i(7, 19)
const CONVEYOR_SIZE := Vector2i(4, 1)
const CONVEYOR_SPEED := Vector2(48.0, 0.0)
# 03: two-way moving platform with a fog occluder under it.
const WAYPOINT_CELL := Vector2i(16, 18)
const WAYPOINT_SIZE := Vector2i(3, 1)
const WAYPOINT_TRAVEL := Vector2(48.0, 0.0)
# 04: falling platform with a rider trigger.
const FALLING_CELL := Vector2i(42, 17)
const FALLING_SIZE := Vector2i(3, 1)
# 05: door pocket. The wall column is solid above the door, open where it stands.
const DOOR_WALL_COLUMN := 48
const DOOR_POCKET_RIGHT := 55
const DOOR_CEILING_ROW := 15
const DOOR_CELL := Vector2i(48, 18)
# 06: phantom-wall pocket. The wall column is solid above the phantom tiles.
const PHANTOM_WALL_COLUMN := 60
const PHANTOM_POCKET_RIGHT := 68
const PHANTOM_CEILING_ROW := 15
const PHANTOM_CELL := Vector2i(60, 18)
# 07: one-way platform; jump up through it, stand on top.
const ONE_WAY_CELL := Vector2i(12, 17)
const ONE_WAY_SIZE := Vector2i(3, 1)

const SIGN_ROW_Y := 88.0
const TITLE_Y := 64.0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var level_root := TEMPLATE.instantiate()
	level_root.set("room_id", ROOM_ID)
	level_root.set("display_name", "组件样板间")
	level_root.set("room_size_chunks", Vector2i(2, 1))
	level_root.set("preview_spawn_id", "start")
	level_root.set("map_color", Color(0.55, 0.85, 0.72))
	_paint_terrain(level_root)
	_place_entities(level_root)

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
		push_error("could not pack the components gallery: %d" % pack_error)
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


# --- Terrain ------------------------------------------------------------------

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
	# Border and floor slab.
	for y: int in HEIGHT_CELLS:
		solid.set_cell(Vector2i(0, y), 0, ATLAS_SOLID)
		solid.set_cell(Vector2i(WIDTH_CELLS - 1, y), 0, ATLAS_SOLID)
	for x: int in WIDTH_CELLS:
		solid.set_cell(Vector2i(x, CEILING_ROW), 0, ATLAS_SOLID)
		for y: int in range(FLOOR_TOP_ROW, HEIGHT_CELLS):
			solid.set_cell(Vector2i(x, y), 0, ATLAS_SOLID)
	_fill(solid, ELEVATOR_LEDGE)
	# Door pocket: solid wall above the door, ceiling, right wall.
	for y: int in range(DOOR_CEILING_ROW, DOOR_CELL.y):
		solid.set_cell(Vector2i(DOOR_WALL_COLUMN, y), 0, ATLAS_SOLID)
	for x: int in range(DOOR_WALL_COLUMN, DOOR_POCKET_RIGHT + 1):
		solid.set_cell(Vector2i(x, DOOR_CEILING_ROW), 0, ATLAS_SOLID)
	for y: int in range(DOOR_CEILING_ROW, FLOOR_TOP_ROW):
		solid.set_cell(Vector2i(DOOR_POCKET_RIGHT, y), 0, ATLAS_SOLID)
	# Phantom pocket: solid wall above the phantom tiles, ceiling, right wall.
	for y: int in range(PHANTOM_CEILING_ROW, PHANTOM_CELL.y):
		solid.set_cell(Vector2i(PHANTOM_WALL_COLUMN, y), 0, ATLAS_SOLID)
	for x: int in range(PHANTOM_WALL_COLUMN, PHANTOM_POCKET_RIGHT + 1):
		solid.set_cell(Vector2i(x, PHANTOM_CEILING_ROW), 0, ATLAS_SOLID)
	for y: int in range(PHANTOM_CEILING_ROW, FLOOR_TOP_ROW):
		solid.set_cell(Vector2i(PHANTOM_POCKET_RIGHT, y), 0, ATLAS_SOLID)
	# The phantom wall replaces the solid cells it covers.
	for cell: Vector2i in [PHANTOM_CELL, PHANTOM_CELL + Vector2i.DOWN]:
		solid.erase_cell(cell)


func _fill(layer: TileMapLayer, rect: Rect2i) -> void:
	for y: int in range(rect.position.y, rect.end.y):
		for x: int in range(rect.position.x, rect.end.x):
			layer.set_cell(Vector2i(x, y), 0, ATLAS_SOLID)


# --- Entities -----------------------------------------------------------------

func _place_entities(level_root: Node) -> void:
	var entities := level_root.get_node("RoomContent/Entities")
	var spawn := entities.get_node_or_null("StartSpawn") as Node2D
	if spawn != null:
		spawn.position = Vector2(2.0 * TILE, FLOOR_TOP_ROW * TILE)
		spawn.set("spawn_id", "start")

	_place_elevator(level_root, entities)
	_place_conveyor(level_root, entities)
	_place_waypoint(level_root, entities)
	_place_falling(level_root, entities)
	_place_one_way(level_root, entities)
	_place_door(level_root, entities)
	_place_phantom_wall(level_root, entities)
	_place_signs(level_root, entities)


func _place_elevator(level_root: Node, entities: Node) -> void:
	var platform := _make_platform("01_Elevator", ELEVATOR_CELL, ELEVATOR_SIZE, Color(0.3, 0.43, 0.52))
	var motion := _add_component(platform, "ElevatorMotion", ELEVATOR_MOTION)
	motion.set("travel", ELEVATOR_TRAVEL)
	motion.set("speed", 56.0)
	_add_rider_trigger(platform, "ElevatorMotion")
	_attach(level_root, entities, platform)


func _place_conveyor(level_root: Node, entities: Node) -> void:
	var platform := _make_platform("02_Conveyor", CONVEYOR_CELL, CONVEYOR_SIZE, Color(0.3, 0.78, 0.82))
	var surface := _add_component(platform, "ConveyorSurface", CONVEYOR_SURFACE)
	surface.set("surface_velocity", CONVEYOR_SPEED)
	_attach(level_root, entities, platform)


func _place_waypoint(level_root: Node, entities: Node) -> void:
	var platform := _make_platform("03_Waypoint", WAYPOINT_CELL, WAYPOINT_SIZE, Color(0.95, 0.7, 0.24))
	var motion := _add_component(platform, "WaypointMotion", WAYPOINT_MOTION)
	motion.set(
		"waypoints",
		PackedVector2Array([Vector2.ZERO, WAYPOINT_TRAVEL])
	)
	motion.set("travel_speed", 32.0)
	motion.set("arrival_pause_seconds", 0.4)
	# The shadow this platform casts on the fog moves with it.
	var occluder := _add_component(platform, "FogOccluder", FOG_OCCLUDER)
	occluder.set("body_path", NodePath(".."))
	_attach(level_root, entities, platform)


func _place_falling(level_root: Node, entities: Node) -> void:
	var platform := _make_platform("04_Falling", FALLING_CELL, FALLING_SIZE, Color(0.91, 0.34, 0.34))
	var motion := _add_component(platform, "FallMotion", FALL_MOTION)
	motion.set("gravity", 900.0)
	motion.set("activation_delay", 0.2)
	_add_rider_trigger(platform, "FallMotion")
	_attach(level_root, entities, platform)


func _place_one_way(level_root: Node, entities: Node) -> void:
	var platform := StaticBody2D.new()
	platform.name = "07_OneWayPlatform"
	platform.position = Vector2(ONE_WAY_CELL) * TILE
	var panel_size := Vector2(ONE_WAY_SIZE) * TILE
	var shape := CollisionShape2D.new()
	shape.name = "CollisionShape2D"
	var box := RectangleShape2D.new()
	box.size = panel_size
	shape.shape = box
	shape.position = panel_size * 0.5
	shape.one_way_collision = true
	platform.add_child(shape)
	var visual := Polygon2D.new()
	visual.name = "Visual"
	visual.color = Color(0.45, 0.75, 0.45)
	visual.polygon = _panel_polygon(panel_size)
	platform.add_child(visual)
	_attach(level_root, entities, platform)


func _place_door(level_root: Node, entities: Node) -> void:
	var door := DOOR_SCENE.instantiate() as Node2D
	door.name = "05_Door"
	door.position = Vector2(DOOR_CELL) * TILE
	var component := door.get_node_or_null("Door")
	if component != null:
		component.set("size_cells", Vector2i(1, 2))
	_attach(level_root, entities, door)


func _place_phantom_wall(level_root: Node, entities: Node) -> void:
	var wall := PHANTOM_WALL_SCENE.instantiate() as TileMapLayer
	wall.name = "06_PhantomWall"
	wall.position = Vector2(PHANTOM_CELL) * TILE
	# Paint exactly the cells that were solid: same tiles, so it reads as wall.
	wall.set_cell(Vector2i.ZERO, 0, ATLAS_SOLID)
	wall.set_cell(Vector2i.DOWN, 0, ATLAS_SOLID)
	_attach(level_root, entities, wall)


func _place_signs(level_root: Node, entities: Node) -> void:
	var signs := Node2D.new()
	signs.name = "Signs"
	entities.add_child(signs)
	signs.owner = level_root
	var title := _make_sign("Copy one station into your own room")
	title.position = Vector2(2.0 * TILE, TITLE_Y)
	signs.add_child(title)
	title.owner = level_root
	for entry: Array in [
		["01 ELEVATOR", ELEVATOR_CELL.x],
		["02 CONVEYOR", CONVEYOR_CELL.x],
		["03 WAYPOINT + FOG", WAYPOINT_CELL.x],
		["07 ONE-WAY", ONE_WAY_CELL.x],
		["04 FALLING", FALLING_CELL.x],
		["05 DOOR [E]", DOOR_CELL.x],
		["06 PHANTOM WALL", PHANTOM_CELL.x],
	]:
		var sign := _make_sign(String(entry[0]))
		sign.position = Vector2(float(int(entry[1])) * TILE, SIGN_ROW_Y)
		signs.add_child(sign)
		sign.owner = level_root


func _make_sign(text: String) -> Label:
	var sign := Label.new()
	sign.text = text
	sign.add_theme_font_size_override("font_size", 8)
	sign.modulate = Color(1.0, 1.0, 1.0, 0.75)
	return sign


# --- Helpers ------------------------------------------------------------------

func _make_platform(
	node_name: String,
	cell: Vector2i,
	cells: Vector2i,
	panel_color: Color
) -> AnimatableBody2D:
	var platform := AnimatableBody2D.new()
	platform.name = node_name
	platform.position = Vector2(cell) * TILE
	platform.set_script(PLATFORM_BODY)
	var panel_size := Vector2(cells) * TILE
	var shape := CollisionShape2D.new()
	shape.name = "CollisionShape2D"
	var box := RectangleShape2D.new()
	box.size = panel_size
	shape.shape = box
	shape.position = panel_size * 0.5
	platform.add_child(shape)
	var visual := Polygon2D.new()
	visual.name = "Visual"
	visual.color = panel_color
	visual.polygon = _panel_polygon(panel_size)
	platform.add_child(visual)
	return platform


func _add_component(platform: Node, node_name: String, script: Script) -> Node:
	# `new()` builds the script's native base (Node2D for the fog occluder,
	# Node for the motion components), which a plain Node cannot carry.
	var component: Node = script.new() as Node
	component.name = node_name
	platform.add_child(component)
	return component


func _add_rider_trigger(platform: Node, target_name: String) -> void:
	var trigger := Area2D.new()
	trigger.name = "RiderTrigger"
	trigger.collision_layer = 0
	trigger.collision_mask = 2
	trigger.monitorable = false
	trigger.set_script(RIDER_TRIGGER)
	var paths: Array[NodePath] = [NodePath("../%s" % target_name)]
	trigger.set("target_paths", paths)
	trigger.set("trigger_once", false)
	var box := RectangleShape2D.new()
	var panel_size := (platform.get_node("CollisionShape2D") as CollisionShape2D).shape.get_rect().size
	box.size = Vector2(panel_size.x + 4.0, 12.0)
	var shape := CollisionShape2D.new()
	shape.name = "CollisionShape2D"
	shape.shape = box
	shape.position = Vector2(panel_size.x * 0.5, 0.0)
	trigger.add_child(shape)
	platform.add_child(trigger)


func _panel_polygon(panel_size: Vector2) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2.ZERO,
		Vector2(panel_size.x, 0.0),
		panel_size,
		Vector2(0.0, panel_size.y),
	])


func _attach(level_root: Node, parent: Node, node: Node) -> void:
	parent.add_child(node)
	_claim(level_root, node)


## Claims only nodes this tool created; instanced sub-scenes keep their own owner.
func _claim(level_root: Node, node: Node) -> void:
	if node.owner == null:
		node.owner = level_root
	for child: Node in node.get_children():
		_claim(level_root, child)
