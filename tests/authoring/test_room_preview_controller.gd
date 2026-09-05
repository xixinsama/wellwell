extends Node

const ROOM_AUTHORING_ROOT: Script = preload("res://scripts/authoring/room_authoring_root.gd")
const ROOM_PREVIEW_CONTROLLER: Script = preload("res://scripts/authoring/room_preview_controller.gd")
const ROOM_ENTRANCE: Script = preload("res://scripts/world/room_entrance.gd")
const SPAWN_POINT: Script = preload("res://scripts/world/spawn_point.gd")
const FOG_OF_WAR: Script = preload("res://scripts/world/fog_of_war.gd")


class PreviewCamera extends Node:
	var bound_target: Node2D

	func bind_target(target: Node2D) -> void:
		bound_target = target


class PreviewHud extends Node:
	var bound_player: Node2D

	func bind_player(player: Node2D) -> void:
		bound_player = player


func run() -> Array[String]:
	var failures: Array[String] = []
	_assert_tree_entry_sets_up_preview(failures)
	_assert_valid_setup_binds_preview_and_keeps_memory_state(failures)
	_assert_invalid_root_does_not_mutate_preview(failures)
	_assert_missing_spawn_does_not_move_player(failures)
	_assert_entrances_only_emit_preview_blocking_signal(failures)
	_assert_repeated_setup_does_not_duplicate_entrance_callbacks(failures)
	return failures


func _assert_tree_entry_sets_up_preview(failures: Array[String]) -> void:
	var root := _make_root("start")
	var spawn := _add_spawn(root, "start", Vector2(24.0, 40.0))
	var player := root.get_node("PreviewOnly/Player") as Node2D
	var controller := _add_controller(root)
	root.move_child(controller, 0)
	controller.call("_ready")
	if player.global_position != spawn.global_position:
		failures.append("preview controller ready handler did not initialize the room")
	root.free()


func _assert_valid_setup_binds_preview_and_keeps_memory_state(failures: Array[String]) -> void:
	var root := _make_root("start")
	var spawn := _add_spawn(root, "start", Vector2(48.0, 72.0))
	var player := root.get_node("PreviewOnly/Player") as Node2D
	var camera := root.get_node("PreviewOnly/PixelCamera2D") as PreviewCamera
	var fog := root.get_node("PreviewOnly/FogOfWar") as FogOfWar
	var hud := root.get_node("PreviewOnly/DebugHud") as PreviewHud
	var controller := _add_controller(root)

	if not controller.setup_preview(root):
		failures.append("valid preview setup failed")
	elif player.global_position != spawn.global_position:
		failures.append("preview setup did not place the player at its room-local spawn")
	elif camera.bound_target != player or hud.bound_player != player:
		failures.append("preview setup did not bind camera and HUD to the preview player")
	elif fog.get("_player") != player:
		failures.append("preview setup did not bind fog to the preview player")
	elif fog.get("_persistence_source") != controller:
		failures.append("preview setup did not bind fog persistence to the controller")

	if controller.get_preview_snapshot() == null:
		failures.append("preview setup did not create an in-memory snapshot")
	elif controller.get_preview_snapshot().world_id != "preview":
		failures.append("preview snapshot did not use the preview namespace")
	if not controller.mark_cell_explored("preview:1,2") or controller.mark_cell_explored("preview:1,2"):
		failures.append("preview cell exploration did not round trip in memory")
	if not controller.mark_chunk_explored("preview:chunk:0,0") or controller.mark_chunk_explored("preview:chunk:0,0"):
		failures.append("preview chunk exploration did not round trip in memory")
	if controller.get_explored_chunks() != ["preview:chunk:0,0"]:
		failures.append("preview explored chunks were not read from the memory snapshot")
	controller.set_entity_state("preview:switch", {"active": true})
	if controller.get_explored_cells() != ["preview:1,2"]:
		failures.append("preview explored cells were not read from the memory snapshot")
	if controller.get_entity_state("preview:switch") != {"active": true}:
		failures.append("preview entity state did not round trip in memory")
	if controller.queue_commit():
		failures.append("preview queue_commit reported a disk commit")
	root.free()


func _assert_invalid_root_does_not_mutate_preview(failures: Array[String]) -> void:
	var root := _make_root("start")
	_add_spawn(root, "start", Vector2(48.0, 72.0))
	root.room_id = ""
	var player := root.get_node("PreviewOnly/Player") as Node2D
	player.position = Vector2(5.0, 7.0)
	var camera := root.get_node("PreviewOnly/PixelCamera2D") as PreviewCamera
	var fog := root.get_node("PreviewOnly/FogOfWar") as FogOfWar
	var controller := _add_controller(root)
	if controller.setup_preview(root):
		failures.append("invalid authoring root was accepted for preview")
	if player.position != Vector2(5.0, 7.0) or camera.bound_target != null:
		failures.append("invalid authoring root mutated player or camera preview state")
	if fog.get("_persistence_source") != null or controller.get_preview_snapshot() != null:
		failures.append("invalid authoring root mutated persistence state")
	root.free()


func _assert_missing_spawn_does_not_move_player(failures: Array[String]) -> void:
	var root := _make_root("missing")
	var player := root.get_node("PreviewOnly/Player") as Node2D
	player.global_position = Vector2(9.0, 11.0)
	var controller := _add_controller(root)
	if controller.setup_preview(root):
		failures.append("preview setup succeeded without its configured spawn")
	if player.global_position != Vector2(9.0, 11.0):
		failures.append("preview setup moved the player before missing-spawn failure")
	root.free()


func _assert_entrances_only_emit_preview_blocking_signal(failures: Array[String]) -> void:
	var root := _make_root("start")
	_add_spawn(root, "start", Vector2.ZERO)
	var entrance: RoomEntrance = ROOM_ENTRANCE.new() as RoomEntrance
	entrance.entity_id = "exit_a"
	entrance.target_room_id = "legacy_room"
	entrance.target_spawn_id = "legacy_spawn"
	root.get_node("RoomContent/Entities").add_child(entrance)
	var controller := _add_controller(root)
	var blocked: Array[RoomEntrance] = []
	controller.transition_blocked.connect(func(value: RoomEntrance) -> void: blocked.append(value))
	if not controller.setup_preview(root):
		failures.append("preview setup failed before entrance blocking test")
	entrance.request_transition()
	if blocked != [entrance]:
		failures.append("preview entrance did not emit exactly one transition_blocked signal")
	if entrance.target_room_id != "legacy_room" or entrance.target_spawn_id != "legacy_spawn":
		failures.append("legacy entrance destinations were not retained as readable migration storage")
	root.free()


func _assert_repeated_setup_does_not_duplicate_entrance_callbacks(failures: Array[String]) -> void:
	var root := _make_root("start")
	_add_spawn(root, "start", Vector2.ZERO)
	var entrance: RoomEntrance = ROOM_ENTRANCE.new() as RoomEntrance
	entrance.entity_id = "exit_a"
	root.get_node("RoomContent/Entities").add_child(entrance)
	var controller := _add_controller(root)
	var blocked: Array[RoomEntrance] = []
	controller.transition_blocked.connect(func(value: RoomEntrance) -> void: blocked.append(value))
	if not controller.setup_preview(root) or not controller.setup_preview(root):
		failures.append("repeated valid preview setup failed")
	entrance.request_transition()
	if blocked.size() != 1:
		failures.append("repeated preview setup duplicated entrance signal callbacks")
	root.free()


func _make_root(preview_spawn_id: String) -> RoomAuthoringRoot:
	var root: RoomAuthoringRoot = ROOM_AUTHORING_ROOT.new() as RoomAuthoringRoot
	root.room_id = "preview_room"
	root.room_size_chunks = Vector2i.ONE
	root.preview_spawn_id = preview_spawn_id
	var content := Node2D.new()
	content.name = "RoomContent"
	root.add_child(content)
	for child_name: String in ["Background", "Terrain", "Entities", "Foreground"]:
		var child := Node2D.new()
		child.name = child_name
		content.add_child(child)
		if child_name == "Terrain":
			for layer_name: String in ["BackTiles", "SolidTiles", "GlassTiles", "VisionBlockTiles", "DetailTiles", "MarkerTiles"]:
				var layer := TileMapLayer.new()
				layer.name = layer_name
				child.add_child(layer)
	var preview := Node2D.new()
	preview.name = "PreviewOnly"
	root.add_child(preview)
	var player := Node2D.new()
	player.name = "Player"
	preview.add_child(player)
	var camera := PreviewCamera.new()
	camera.name = "PixelCamera2D"
	preview.add_child(camera)
	var fog: FogOfWar = FOG_OF_WAR.new() as FogOfWar
	fog.name = "FogOfWar"
	preview.add_child(fog)
	var hud := PreviewHud.new()
	hud.name = "DebugHud"
	preview.add_child(hud)
	return root


func _add_spawn(root: RoomAuthoringRoot, spawn_id: String, position: Vector2) -> SpawnPoint:
	var spawn: SpawnPoint = SPAWN_POINT.new() as SpawnPoint
	spawn.spawn_id = spawn_id
	spawn.global_position = position
	root.get_node("RoomContent/Entities").add_child(spawn)
	return spawn


func _add_controller(root: RoomAuthoringRoot) -> Node:
	var controller: Node = ROOM_PREVIEW_CONTROLLER.new() as Node
	controller.name = "RoomPreviewController"
	root.add_child(controller)
	return controller
