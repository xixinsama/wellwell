extends Node

const PIXEL_CAMERA: Script = preload("res://addons/platformer_kit/camera/pixel_camera_2d.gd")
const DEBUG_HUD: Script = preload("res://addons/platformer_debug/runtime/debug_hud.gd")
const FOG_OF_WAR: Script = preload("res://addons/metroidvania_kit/map/discovery/fog_of_war.gd")
const ROOM_DATA: Script = preload("res://addons/platformer_kit/world/data/room_data.gd")


class DebugPlayer extends Node:
	func get_debug_state() -> Dictionary:
		return {"velocity": Vector2(12.0, -4.0), "on_floor": true}


class PersistenceSource extends Node:
	func get_explored_cells() -> Array[String]:
		return ["room_b:80,23"]


func run() -> Array[String]:
	var failures: Array[String] = []
	_assert_explicit_player_bindings(failures)
	_assert_fog_binds_explicit_room_context(failures)
	return failures


func _assert_explicit_player_bindings(failures: Array[String]) -> void:
	var root := Node.new()
	var player := Node2D.new()
	player.global_position = Vector2(17.25, 28.75)
	root.add_child(player)
	var camera := PIXEL_CAMERA.new() as Camera2D
	root.add_child(camera)
	add_child(root)
	camera.bind_target(player)
	if camera.target != player or camera.global_position != player.global_position.round():
		failures.append("pixel camera did not retain the explicit player binding")
	var hud := DEBUG_HUD.new() as Control
	var label := Label.new()
	label.name = "Label"
	hud.add_child(label)
	root.add_child(hud)
	var debug_player := DebugPlayer.new()
	root.add_child(debug_player)
	hud.bind_player(debug_player)
	hud._process(0.0)
	if hud.player != debug_player or not label.text.contains("relative 12.0, -4.0"):
		failures.append("debug HUD did not retain the explicit player binding")
	remove_child(root)
	root.free()


func _assert_fog_binds_explicit_room_context(failures: Array[String]) -> void:
	var root := Node2D.new()
	var player := Node2D.new()
	player.global_position = Vector2(4.0, 4.0)
	root.add_child(player)
	var terrain := _make_terrain_root()
	root.add_child(terrain)
	var fog := FOG_OF_WAR.new() as Node2D
	root.add_child(fog)
	fog.bind_player(player)
	var persistence := PersistenceSource.new()
	root.add_child(persistence)
	fog.bind_persistence_source(persistence)
	add_child(root)
	var room: Resource = ROOM_DATA.new()
	room.room_id = "room_b"
	room.room_size_chunks = Vector2i.ONE
	if not fog.bind_room_with_origin(room, terrain, Vector2i(2, 1)):
		failures.append("FogOfWar rejected explicit room and terrain context")
	elif fog.level_id != "room_b" or fog.map_origin_cell != Vector2i(80, 23) or fog.map_size_cells != Vector2i(40, 23):
		failures.append("FogOfWar did not derive exact room fog bounds")
	elif not fog.is_cell_explored(Vector2i(80, 23)):
		failures.append("FogOfWar did not restore exploration for the explicit room")
	fog.clear_room()
	if fog.get("_vision_block_tiles") != null or not fog.currently_visible.is_empty():
		failures.append("FogOfWar clear_room retained explicit room bindings")
	remove_child(root)
	root.free()


func _make_terrain_root() -> Node2D:
	var root := Node2D.new()
	var background := Node2D.new()
	background.name = "Background"
	root.add_child(background)
	var terrain := Node2D.new()
	terrain.name = "Terrain"
	root.add_child(terrain)
	for layer_name: String in ["BackTiles", "SolidTiles", "GlassTiles", "VisionBlockTiles", "DetailTiles", "MarkerTiles"]:
		var layer := TileMapLayer.new()
		layer.name = layer_name
		terrain.add_child(layer)
	return root
