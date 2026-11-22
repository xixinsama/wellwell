extends Node

## Contract for the authoring room's preview spawn: an authored ID is used while
## it exists, a renamed preview spawn follows its SpawnPoint, and a stale ID falls
## back to the room's first spawn instead of failing the bake.

const ROOM_AUTHORING_ROOT: Script = preload("res://addons/world_editor/authoring/room/room_authoring_root.gd")
const ROOM_AUTHORING_CONTRACT: Script = preload("res://addons/world_editor/authoring/room/room_authoring_contract.gd")
const ROOM_PREVIEW_CONTROLLER: Script = preload("res://addons/world_editor/authoring/room/room_preview_controller.gd")
const SPAWN_POINT: Script = preload("res://addons/platformer_kit/world/entities/spawn_point.gd")


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
	_assert_no_spawns_resolves_empty(failures)
	_assert_first_spawn_is_the_fallback(failures)
	_assert_rename_follows_the_preview_spawn(failures)
	_assert_rename_ignores_other_spawns(failures)
	_assert_stale_preview_is_repaired_on_rename(failures)
	_assert_preview_controller_uses_the_fallback(failures)
	return failures


func _assert_no_spawns_resolves_empty(failures: Array[String]) -> void:
	var root := _make_root("start")
	if not root.resolve_preview_spawn_id().is_empty():
		failures.append("a room without spawns resolved a preview spawn")
	if not String(root.get_manifest().get("preview_spawn_id", "x")).is_empty():
		failures.append("manifest kept a preview spawn without any SpawnPoint")
	root.free()


func _assert_first_spawn_is_the_fallback(failures: Array[String]) -> void:
	var root := _make_root("preview_a")
	_add_spawn(root, "zeta")
	_add_spawn(root, "start")
	if root.resolve_preview_spawn_id() != "start":
		failures.append("stale preview_spawn_id did not fall back to the first sorted spawn")
	if root.get_manifest().get("preview_spawn_id") != "start":
		failures.append("manifest did not use the resolved preview spawn")
	var result: Dictionary = ROOM_AUTHORING_CONTRACT.validate(root)
	if not (result.get("errors", []) as Array).is_empty():
		failures.append("stale preview_spawn_id still fails validation: %s" % result.get("errors"))
	if (result.get("warnings", []) as Array).is_empty():
		failures.append("stale preview_spawn_id did not produce a warning")
	root.free()


func _assert_rename_follows_the_preview_spawn(failures: Array[String]) -> void:
	var root := _make_root("start")
	_add_spawn(root, "start")
	_add_spawn(root, "entry")
	var spawn := _find_spawn(root, "start")
	if spawn == null:
		failures.append("test spawn could not be found")
		root.free()
		return
	spawn.spawn_id = "start01"
	if root.preview_spawn_id != "start01":
		failures.append("preview_spawn_id did not follow its renamed SpawnPoint")
	if root.resolve_preview_spawn_id() != "start01":
		failures.append("resolved preview spawn did not follow the rename")
	root.free()


func _assert_rename_ignores_other_spawns(failures: Array[String]) -> void:
	var root := _make_root("start")
	_add_spawn(root, "start")
	var other := _add_spawn(root, "entry")
	other.spawn_id = "entry01"
	if root.preview_spawn_id != "start":
		failures.append("renaming an unrelated SpawnPoint changed preview_spawn_id")
	root.free()


func _assert_stale_preview_is_repaired_on_rename(failures: Array[String]) -> void:
	var root := _make_root("gone")
	var spawn := _add_spawn(root, "entry")
	spawn.spawn_id = "entry01"
	if root.preview_spawn_id != "entry01":
		failures.append("a stale preview_spawn_id did not adopt the renamed spawn")
	root.free()


func _assert_preview_controller_uses_the_fallback(failures: Array[String]) -> void:
	var root := _make_root("preview_a")
	var spawn := _add_spawn(root, "start")
	spawn.position = Vector2(48.0, 72.0)
	var player := root.get_node("PreviewOnly/Player") as Node2D
	var controller: Node = ROOM_PREVIEW_CONTROLLER.new() as Node
	controller.name = "RoomPreviewController"
	root.add_child(controller)
	if not bool(controller.call("setup_preview", root)):
		failures.append("preview setup failed with a stale preview_spawn_id")
	elif player.position != spawn.position:
		failures.append("preview did not place the player at the fallback spawn")
	var snapshot: RefCounted = controller.call("get_preview_snapshot")
	if snapshot == null:
		failures.append("preview did not create a snapshot for the fallback spawn")
	elif String(snapshot.get("respawn_spawn_id")) != "start":
		failures.append("preview snapshot kept the stale spawn ID")
	root.free()


func _make_root(preview_id: String) -> RoomAuthoringRoot:
	var root: RoomAuthoringRoot = ROOM_AUTHORING_ROOT.new() as RoomAuthoringRoot
	root.room_id = "preview_room"
	root.room_size_chunks = Vector2i.ONE
	root.preview_spawn_id = preview_id
	var content := Node2D.new()
	content.name = "RoomContent"
	root.add_child(content)
	for child_name: String in ["Background", "Terrain", "Entities", "Foreground"]:
		var child := Node2D.new()
		child.name = child_name
		content.add_child(child)
		if child_name == "Terrain":
			for layer_name: String in ["BackTiles", "SolidTiles", "DetailTiles"]:
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
	var hud := PreviewHud.new()
	hud.name = "DebugHud"
	preview.add_child(hud)
	var fog := Node.new()
	fog.name = "FogOfWar"
	preview.add_child(fog)
	return root


func _add_spawn(root: Node, spawn_id: String) -> SpawnPoint:
	var spawn: SpawnPoint = SPAWN_POINT.new() as SpawnPoint
	spawn.spawn_id = spawn_id
	root.get_node("RoomContent/Entities").add_child(spawn)
	return spawn


func _find_spawn(root: Node, spawn_id: String) -> SpawnPoint:
	for child: Node in root.get_node("RoomContent/Entities").get_children():
		if child is SpawnPoint and (child as SpawnPoint).spawn_id == spawn_id:
			return child as SpawnPoint
	return null

