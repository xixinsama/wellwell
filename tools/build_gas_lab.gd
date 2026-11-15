extends SceneTree

## Builds the gas lab source room: three platform rows on the left wall and three
## wall vents, one per gas, all pointing into the room.
##
## Run it once (and again after changing the layout):
##   godot --headless --path . -s res://tools/build_gas_lab.gd
## It writes the source scene, bakes it through RoomBaker, and prints the output
## paths. Add the baked RoomData to a world afterwards (test_world.tres).

const TEMPLATE := preload("res://scenes/rooms/template/level_template.tscn")
const ROOM_BAKER := preload("res://addons/world_editor/authoring/room/room_baker.gd")

const SOURCE_PATH := "res://scenes/levels/test/gas_lab.tscn"
const ROOM_ID := "gas_lab"
const WIDTH_CELLS := 40
const HEIGHT_CELLS := 23
const TILE := 8

const ATLAS_BACKGROUND := Vector2i(0, 5)
const ATLAS_SOLID := Vector2i(1, 0)
const ATLAS_FILL := Vector2i(0, 0)

# Platform rows (tile rows): floor is the top of the bedrock, then three rows.
const FLOOR_ROW := 21
const PLATFORM_ROWS: Array[int] = [18, 15, 12]
const PLATFORM_SPANS: Array[Vector2i] = [
	Vector2i(3, 12),
	Vector2i(15, 24),
	Vector2i(27, 36),
]


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var root := TEMPLATE.instantiate()
	root.set("room_id", ROOM_ID)
	root.set("display_name", "气体实验室")
	root.set("room_size_chunks", Vector2i.ONE)
	root.set("preview_spawn_id", "start")
	root.set("map_color", Color(0.55, 0.85, 0.35))
	_paint_terrain(root)
	_place_entities(root)

	var packed := PackedScene.new()
	var pack_error := packed.pack(root)
	if pack_error != OK:
		push_error("could not pack the gas lab: %d" % pack_error)
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
	for warning: String in bake_result.get("warnings", []):
		print("bake warning: %s" % warning)
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

	# Border.
	for y: int in HEIGHT_CELLS:
		solid.set_cell(Vector2i(0, y), 0, ATLAS_SOLID)
		solid.set_cell(Vector2i(WIDTH_CELLS - 1, y), 0, ATLAS_SOLID)
	for x: int in WIDTH_CELLS:
		solid.set_cell(Vector2i(x, 0), 0, ATLAS_SOLID)
		solid.set_cell(Vector2i(x, HEIGHT_CELLS - 2), 0, ATLAS_SOLID)
		solid.set_cell(Vector2i(x, HEIGHT_CELLS - 1), 0, ATLAS_SOLID)

	# Three staggered platform rows above the walkable floor.
	for row_index: int in PLATFORM_ROWS.size():
		var row := PLATFORM_ROWS[row_index]
		var span := PLATFORM_SPANS[row_index]
		for x: int in range(span.x, span.y + 1):
			solid.set_cell(Vector2i(x, row), 0, ATLAS_SOLID)
		# Small bracket under each end so the platforms read as built, not painted.
		solid.set_cell(Vector2i(span.x, row + 1), 0, ATLAS_FILL)
		solid.set_cell(Vector2i(span.y, row + 1), 0, ATLAS_FILL)


func _place_entities(root: Node) -> void:
	var entities := root.get_node("RoomContent/Entities")
	var spawn := entities.get_node_or_null("StartSpawn") as Node2D
	if spawn != null:
		spawn.position = Vector2(24.0, FLOOR_ROW * TILE)
		spawn.set("spawn_id", "start")

	# One vent per gas, stacked on the left wall and all blowing into the room.
	var vents := [
		{"name": "LightVent", "channel": GasVent.Channel.LIGHT, "y": 8, "rate": 2.2, "jet": 380.0},
		{"name": "NeutralVent", "channel": GasVent.Channel.NEUTRAL, "y": 11, "rate": 2.2, "jet": 380.0},
		{"name": "HeavyVent", "channel": GasVent.Channel.HEAVY, "y": 14, "rate": 2.2, "jet": 380.0},
	]
	for entry: Dictionary in vents:
		var vent := GasVent.new()
		vent.name = String(entry["name"])
		vent.position = Vector2(10.0, float(entry["y"]) * TILE)
		vent.direction = Vector2.RIGHT
		vent.radius = 20.0
		vent.rate = float(entry["rate"])
		vent.jet_speed = float(entry["jet"])
		vent.channel = int(entry["channel"])
		vent.vent_id = String(entry["name"])
		_attach(root, entities, vent)

	var warm := FogLight.new()
	warm.name = "LabLightTop"
	warm.position = Vector2(56.0, 40.0)
	warm.light_id = "lab_top"
	warm.radius = 90.0
	warm.energy = 1.0
	warm.color = Color(1.0, 0.86, 0.6)
	warm.flicker = 0.1
	_attach(root, entities, warm)

	var cool := FogLight.new()
	cool.name = "LabLightBottom"
	cool.position = Vector2(264.0, 148.0)
	cool.light_id = "lab_bottom"
	cool.radius = 100.0
	cool.energy = 0.9
	cool.color = Color(0.55, 0.8, 1.0)
	cool.flicker = 0.06
	cool.flicker_speed = 2.0
	_attach(root, entities, cool)

	# Lit like the water hall: the exploration fog must not clip the plumes.
	var hall_light := FogZone.new()
	hall_light.name = "GasLabLight"
	hall_light.position = Vector2.ZERO
	hall_light.mode = FogZone.Mode.LIGHT
	hall_light.size_cells = Vector2i(WIDTH_CELLS, HEIGHT_CELLS)
	hall_light.zone_id = "gas_lab_lit"
	_attach(root, entities, hall_light)


func _attach(root: Node, parent: Node, node: Node) -> void:
	parent.add_child(node)
	node.owner = root
