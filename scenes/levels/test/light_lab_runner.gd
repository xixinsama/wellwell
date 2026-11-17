extends Control

## Standalone runner for the lighting demo room.
##
## It binds the room to the light field, the fog and the grid water in code, so
## the scene can be opened and looked at without a world resource. Everything the
## light map needs (walls as occluders, lamps, fireflies) is authored in
## `scenes/levels/test/light_lab.tscn`; rebuild it with
## `godot --headless --path . -s res://tools/build_light_lab.gd`.

const ROOM_PATH := "res://scenes/levels/test/light_lab.tscn"
const ROOM_DATA_PATH := "res://resources/rooms/generated/light_lab.tres"

@onready var viewport: SubViewport = $SubViewportContainer/SubViewport


func _ready() -> void:
	var room: Node = (load(ROOM_PATH) as PackedScene).instantiate()
	# The outline looks for the decorated rooms under TerrainRoot, like the game.
	var rooms := Node2D.new()
	rooms.name = "TerrainRoot"
	viewport.add_child(rooms)
	rooms.add_child(room)
	# The template ships a whole preview rig (its own player, camera and fog);
	# this scene builds that itself.
	var preview := room.get_node_or_null("PreviewOnly")
	if preview != null:
		room.remove_child(preview)
		preview.queue_free()

	var room_content: Node = room.get_node("RoomContent")
	var room_data: Resource = load(ROOM_DATA_PATH)

	var player: Node2D = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	viewport.add_child(player)
	player.global_position = _spawn_position(room_content)

	var camera := Camera2D.new()
	camera.name = "Camera"
	camera.position = Vector2(160.0, 88.0)
	viewport.add_child(camera)
	camera.make_current()

	var fog: Node2D = (load("res://addons/metroidvania_kit/map/discovery/fog_of_war.gd") as Script).new() as Node2D
	fog.name = "FogOfWar"
	fog.z_index = 10
	fog.z_as_relative = false
	viewport.add_child(fog)
	var grid: Node2D = (load("res://addons/fluid_kit/runtime/water/water_grid.gd") as Script).new() as Node2D
	grid.name = "WaterGrid"
	viewport.add_child(grid)
	var field: Node2D = (load("res://scripts/world/light_field.gd") as Script).new() as Node2D
	field.name = "LightField"
	viewport.add_child(field)
	var highlight: Node2D = (load("res://scripts/world/terrain_highlight.gd") as Script).new() as Node2D
	highlight.name = "TerrainHighlight"
	highlight.set("layer_path", NodePath("RoomContent/Terrain/SolidTiles"))
	viewport.add_child(highlight)

	fog.call("bind_player", player)
	field.call("bind_player", player)
	# Order matters: the fog builds its mask while binding, and the field hands
	# its map over afterwards. The outline decorates once the room is in place.
	for extension: Node in [grid, fog, field]:
		extension.call("bind_room_with_origin", room_data, room_content, Vector2i.ZERO)
	highlight.call("decorate_rooms")


func _spawn_position(room_content: Node) -> Vector2:
	var spawn := room_content.get_node_or_null("Entities/StartSpawn") as Node2D
	if spawn != null:
		return spawn.global_position
	return Vector2(24.0, 144.0)
