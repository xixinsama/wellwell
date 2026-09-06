extends Node

const PIXEL_CAMERA: Script = preload("res://scripts/camera/pixel_camera_2d.gd")
const DEBUG_HUD: Script = preload("res://scripts/tools/debug_hud.gd")
const FOG_OF_WAR: Script = preload("res://scripts/world/fog_of_war.gd")
const ROOM_DATA: Script = preload("res://scripts/world/room_data.gd")


class DebugPlayer extends Node:

	var velocity := Vector2(12.0, -4.0)

	func get_debug_state() -> Dictionary:
		return {
			"velocity": velocity,
			"on_floor": true,
			"jump_buffer_remaining": 0.125,
			"coyote_remaining": 0.25,
		}


class PersistenceSource extends Node:

	var explored_cells: Array[String] = []

	func get_explored_cells() -> Array[String]:
		return explored_cells.duplicate()


func run() -> Array[String]:
	var failures: Array[String] = []
	_assert_pixel_camera_binds_without_node_path(failures)
	_assert_debug_hud_binds_without_node_path(failures)
	_assert_fog_binds_player_and_room_without_node_paths(failures)
	_assert_explicit_bindings_override_nonempty_paths(failures)
	_assert_node_path_fallbacks_remain_available(failures)
	return failures


func _assert_pixel_camera_binds_without_node_path(failures: Array[String]) -> void:
	var root := Node2D.new()
	var player := Node2D.new()
	player.name = "Player"
	player.position = Vector2(17.25, 28.75)
	root.add_child(player)
	var camera: Camera2D = PIXEL_CAMERA.new() as Camera2D
	camera.name = "PixelCamera2D"
	camera.target_path = NodePath()
	root.add_child(camera)
	add_child(root)

	if not camera.has_method("bind_target"):
		failures.append("missing production API: PixelCamera2D.bind_target")
	else:
		camera.call("bind_target", player)
		if camera.get("target") != player:
			failures.append("PixelCamera2D.bind_target did not store the target")
		if camera.get("smoothed_position") != player.global_position:
			failures.append("PixelCamera2D.bind_target did not synchronize smoothed position")
		if camera.global_position != player.global_position.round():
			failures.append("PixelCamera2D.bind_target did not synchronize rounded global position")

		player.global_position = Vector2(49.5, 62.25)
		camera.call("_physics_process", 1.0 / 60.0)
		var smoothed: Vector2 = camera.get("smoothed_position")
		if smoothed == Vector2(17.25, 28.75):
			failures.append("PixelCamera2D did not follow the bound target during physics")
		if camera.global_position != smoothed.round():
			failures.append("PixelCamera2D physics position was not pixel rounded")

	root.free()


func _assert_debug_hud_binds_without_node_path(failures: Array[String]) -> void:
	var root := Node.new()
	var hud: Control = DEBUG_HUD.new() as Control
	var label := Label.new()
	label.name = "Label"
	hud.add_child(label)
	root.add_child(hud)
	var player := DebugPlayer.new()
	root.add_child(player)
	hud.player_path = NodePath()
	add_child(root)

	if not hud.has_method("bind_player"):
		failures.append("missing production API: DebugHud.bind_player")
	else:
		hud.call("bind_player", player)
		hud.call("_process", 0.0)
		if hud.get("player") != player:
			failures.append("DebugHud.bind_player did not store the player")
		if not label.text.contains("vel 12.0, -4.0") or not label.text.contains("floor true"):
			failures.append("DebugHud did not render the bound player's debug state")

	root.free()


func _assert_fog_binds_player_and_room_without_node_paths(failures: Array[String]) -> void:
	var root := Node2D.new()
	var player := Node2D.new()
	player.name = "Player"
	player.position = Vector2(4.0, 4.0)
	root.add_child(player)
	var fog: Node2D = FOG_OF_WAR.new() as Node2D
	fog.name = "FogOfWar"
	fog.player_path = NodePath()
	root.add_child(fog)
	var terrain := _make_terrain_root()
	root.add_child(terrain)
	var persistence := PersistenceSource.new()
	persistence.explored_cells = ["room_b:80,23"]
	root.add_child(persistence)
	fog.call("bind_player", player)
	fog.call("bind_persistence_source", persistence)
	fog.call("bind_room", _make_room("room_b", Vector2i(2, 1)), terrain)
	add_child(root)

	if not fog.has_method("bind_player"):
		failures.append("missing production API: FogOfWar.bind_player")
	if not fog.has_method("bind_room"):
		failures.append("missing production API: FogOfWar.bind_room")
	if not fog.has_method("clear_room"):
		failures.append("missing production API: FogOfWar.clear_room")
	if fog.has_method("bind_player"):
		fog.call("bind_player", player)
		if fog.get("_player") != player:
			failures.append("FogOfWar.bind_player did not store the player")
	if fog.has_method("bind_room"):
		fog.call("bind_persistence_source", persistence)
		var room: Resource = _make_room("room_b", Vector2i(2, 1))
		var result: Variant = fog.call("bind_room", room, terrain)
		if result != true:
			failures.append("FogOfWar.bind_room rejected a valid terrain root")
		else:
			if fog.get("level_id") != "room_b":
				failures.append("FogOfWar.bind_room did not set level_id")
			if fog.get("map_origin_cell") != Vector2i(80, 23):
				failures.append("FogOfWar.bind_room did not set room cell origin")
			if fog.get("map_size_cells") != Vector2i(40, 23):
				failures.append("FogOfWar.bind_room did not set room cell bounds")
			if not fog.is_cell_explored(Vector2i(80, 23)):
				failures.append("FogOfWar.bind_room did not load new room exploration")
		if fog.has_method("clear_room"):
			fog.call("clear_room")
			if fog.get("_solid_tiles") != null or fog.get("_vision_block_tiles") != null or fog.get("_glass_tiles") != null:
				failures.append("FogOfWar.clear_room did not detach tile layers")
			if not fog.currently_visible.is_empty() or not fog.get("_explored_cells").is_empty():
				failures.append("FogOfWar.clear_room did not clear fog state")

	root.free()


func _assert_node_path_fallbacks_remain_available(failures: Array[String]) -> void:
	var root := Node2D.new()
	var player := Node2D.new()
	player.name = "Player"
	player.position = Vector2(12.0, 20.0)
	root.add_child(player)
	var camera: Camera2D = PIXEL_CAMERA.new() as Camera2D
	camera.target_path = NodePath("../Player")
	root.add_child(camera)
	var fog: Node2D = FOG_OF_WAR.new() as Node2D
	fog.player_path = NodePath("../Player")
	var solid := TileMapLayer.new()
	solid.name = "SolidTiles"
	root.add_child(solid)
	fog.solid_tiles_path = NodePath("../SolidTiles")
	fog.map_size_cells = Vector2i(2, 2)
	root.add_child(fog)
	add_child(root)

	if camera.get("target") != player:
		failures.append("PixelCamera2D NodePath fallback no longer binds")
	if fog.get("_player") != player:
		failures.append("FogOfWar NodePath fallback no longer binds")

	var hud_root := Node.new()
	var hud: Control = DEBUG_HUD.new() as Control
	var label := Label.new()
	label.name = "Label"
	hud.add_child(label)
	hud.player_path = NodePath("../Player")
	hud_root.add_child(hud)
	var hud_player := Node.new()
	hud_player.name = "Player"
	hud_player.set_script(null)
	hud_root.add_child(hud_player)
	add_child(hud_root)
	if hud.get("player") != hud_player:
		failures.append("DebugHud NodePath fallback no longer binds")

	root.free()
	hud_root.free()


func _assert_explicit_bindings_override_nonempty_paths(failures: Array[String]) -> void:
	var root := Node2D.new()
	var fallback := Node2D.new()
	fallback.name = "Fallback"
	root.add_child(fallback)
	var explicit := Node2D.new()
	explicit.name = "Explicit"
	explicit.position = Vector2(24.0, 16.0)
	root.add_child(explicit)
	var camera: Camera2D = PIXEL_CAMERA.new() as Camera2D
	camera.target_path = NodePath("../Fallback")
	camera.call("bind_target", explicit)
	root.add_child(camera)
	var fog: Node2D = FOG_OF_WAR.new() as Node2D
	fog.player_path = NodePath("../Fallback")
	fog.call("bind_player", explicit)
	var solid := TileMapLayer.new()
	solid.name = "SolidTiles"
	root.add_child(solid)
	fog.solid_tiles_path = NodePath("../SolidTiles")
	var legacy_vision := TileMapLayer.new()
	legacy_vision.name = "LegacyVision"
	root.add_child(legacy_vision)
	var legacy_glass := TileMapLayer.new()
	legacy_glass.name = "LegacyGlass"
	root.add_child(legacy_glass)
	fog.vision_block_tiles_path = NodePath("../LegacyVision")
	fog.glass_tiles_path = NodePath("../LegacyGlass")
	var explicit_terrain := _make_terrain_root()
	explicit_terrain.name = "ExplicitTerrain"
	root.add_child(explicit_terrain)
	fog.call("bind_room", _make_room("explicit_room", Vector2i.ZERO), explicit_terrain)
	root.add_child(fog)
	var fallback_debug := DebugPlayer.new()
	fallback_debug.name = "FallbackDebug"
	root.add_child(fallback_debug)
	var explicit_debug := DebugPlayer.new()
	explicit_debug.name = "ExplicitDebug"
	root.add_child(explicit_debug)
	var hud: Control = DEBUG_HUD.new() as Control
	var label := Label.new()
	label.name = "Label"
	hud.add_child(label)
	hud.player_path = NodePath("../FallbackDebug")
	hud.call("bind_player", explicit_debug)
	root.add_child(hud)
	add_child(root)
	if camera.get("target") != explicit:
		failures.append("camera ready lifecycle replaced an explicit target binding")
	if fog.get("_player") != explicit:
		failures.append("fog ready lifecycle replaced an explicit player binding")
	if fog.get("_solid_tiles") != explicit_terrain.get_node("Terrain/SolidTiles"):
		failures.append("fog ready lifecycle replaced explicit room tile bindings")
	if hud.get("player") != explicit_debug:
		failures.append("HUD ready lifecycle replaced an explicit player binding")
	camera.call("bind_target", null)
	fog.call("bind_player", null)
	camera.call("_physics_process", 0.0)
	fog.call("reveal_from_player")
	if camera.get("target") != null or fog.get("_player") != null:
		failures.append("explicit null binding reattached a NodePath fallback")
	root.free()


func _make_room(room_id: String, origin_chunk: Vector2i) -> Resource:
	var room: Resource = ROOM_DATA.new()
	room.room_id = room_id
	room.room_origin_chunk = origin_chunk
	room.room_size_chunks = Vector2i.ONE
	return room


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
