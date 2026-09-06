extends Node

const ROOM_DATA: Script = preload("res://scripts/world/room_data.gd")
const WORLD_DATA: Script = preload("res://scripts/world/world_data.gd")
const ROOM_AUTHORING_ROOT: Script = preload("res://scripts/authoring/room_authoring_root.gd")
const WORLD_BAKER_PATH := "res://scripts/authoring/world_baker.gd"
const WORLD_PATH := "user://task7_world_baker_world.tres"
const SOURCE_SCENE_PATH := "user://task7_world_baker_source.tscn"
const RUNTIME_SCENE_PATH := "user://task7_world_baker_runtime.tscn"
const PREVIEW_RUNTIME_SCENE_PATH := "user://task7_world_baker_preview_runtime.tscn"
const TERRAIN_RUNTIME_SCENE_PATH := "user://task7_world_baker_terrain_runtime.tscn"
const TERRAIN_SCENE_PATH := "user://task7_world_baker_terrain.tscn"
const BROKEN_TERRAIN_SCENE_PATH := "user://task7_world_baker_broken_terrain.tscn"
const WRONG_ROOT_TERRAIN_SCENE_PATH := "user://task7_world_baker_wrong_root_terrain.tscn"
const WRONG_RESOURCE_PATH := "user://task7_world_baker_wrong_resource.tres"
const MISSING_TERRAIN_PATH := "user://task7_world_baker_missing_terrain.tscn"
const TERRAIN_LAYER_NAMES: Array[String] = [
	"BackTiles", "SolidTiles", "GlassTiles", "VisionBlockTiles", "DetailTiles", "MarkerTiles"
]


class FailingPromoteBaker extends "res://scripts/authoring/world_baker.gd":
	func _promote_staged_file(_staged_path: String, _final_path: String) -> Error:
		return ERR_CANT_CREATE


func run() -> Array[String]:
	var failures: Array[String] = []
	var baker_script := _load_baker_script(failures)
	if baker_script == null:
		return failures
	var baker: Object = baker_script.new()
	if baker == null:
		failures.append("WorldBaker could not be instantiated")
		return failures
	if not baker.has_method("bake"):
		failures.append("WorldBaker missing method: bake")
		return failures
	_remove_user_files()
	var fixture_error := _save_fixtures()
	if fixture_error != OK:
		failures.append("world baker fixture save failed: %d" % fixture_error)
		_remove_user_files()
		return failures
	_assert_resource_path_is_required(baker, failures)
	_assert_bake_saves_valid_world(baker, failures)
	_assert_wrong_resource_types_are_rejected(baker, failures)
	_assert_preview_runtime_is_rejected(baker, failures)
	_assert_runtime_terrain_is_rejected(baker, failures)
	_assert_invalid_terrain_does_not_replace_old_world(baker, failures)
	_assert_failed_world_promotion_restores_old_file(failures)
	_remove_user_files()
	return failures


func _load_baker_script(failures: Array[String]) -> Script:
	if not FileAccess.file_exists(WORLD_BAKER_PATH):
		failures.append("missing production API: %s" % WORLD_BAKER_PATH)
		return null
	var baker_script := load(WORLD_BAKER_PATH) as Script
	if baker_script == null:
		failures.append("could not load production API: %s" % WORLD_BAKER_PATH)
	return baker_script


func _assert_bake_saves_valid_world(baker: Object, failures: Array[String]) -> void:
	var old_world: Resource = _make_world("old_world", TERRAIN_SCENE_PATH, RUNTIME_SCENE_PATH)
	var save_error := ResourceSaver.save(old_world, WORLD_PATH)
	if save_error != OK:
		failures.append("could not save old world fixture: %d" % save_error)
		return
	var candidate: Resource = _load_world()
	if candidate == null:
		failures.append("could not reload old world fixture")
		return
	candidate.world_id = "baked_world"
	var result: Dictionary = baker.call("bake", candidate)
	_assert_result_envelope(result, "valid bake", failures)
	if not bool(result.get("ok", false)):
		failures.append("valid world was not baked: %s" % str(result.get("errors", [])))
		return
	var reloaded: Resource = _load_world()
	if reloaded == null or reloaded.world_id != "baked_world":
		failures.append("successful bake did not save to world.resource_path")


func _assert_resource_path_is_required(baker: Object, failures: Array[String]) -> void:
	var unsaved_world: Resource = _make_world("unsaved_world", TERRAIN_SCENE_PATH, RUNTIME_SCENE_PATH)
	if not unsaved_world.resource_path.is_empty():
		failures.append("fresh WorldData fixture unexpectedly already had a resource_path")
	var result: Dictionary = baker.call("bake", unsaved_world)
	_assert_result_envelope(result, "empty resource_path", failures)
	if bool(result.get("ok", false)):
		failures.append("WorldBaker accepted a world with empty resource_path")


func _assert_wrong_resource_types_are_rejected(baker: Object, failures: Array[String]) -> void:
	var path_fields: Array[String] = ["source_scene_path", "scene_path", "terrain_scene_path"]
	for path_field: String in path_fields:
		var candidate: Resource = _load_world()
		if candidate == null:
			failures.append("could not reload world before wrong %s test" % path_field)
			continue
		var room: Resource = candidate.rooms[0]
		room.set(path_field, WRONG_RESOURCE_PATH)
		var result: Dictionary = baker.call("bake", candidate)
		_assert_result_envelope(result, "wrong %s type" % path_field, failures)
		if bool(result.get("ok", false)):
			failures.append("WorldBaker accepted a non-PackedScene %s" % path_field)


func _assert_preview_runtime_is_rejected(baker: Object, failures: Array[String]) -> void:
	var candidate: Resource = _load_world()
	if candidate == null:
		failures.append("could not reload world before PreviewOnly test")
		return
	(candidate.rooms[0] as Resource).scene_path = PREVIEW_RUNTIME_SCENE_PATH
	var result: Dictionary = baker.call("bake", candidate)
	_assert_result_envelope(result, "PreviewOnly runtime", failures)
	if bool(result.get("ok", false)):
		failures.append("WorldBaker accepted runtime scene containing PreviewOnly")


func _assert_runtime_terrain_is_rejected(baker: Object, failures: Array[String]) -> void:
	var candidate: Resource = _load_world()
	if candidate == null:
		failures.append("could not reload world before runtime terrain test")
		return
	(candidate.rooms[0] as Resource).scene_path = TERRAIN_RUNTIME_SCENE_PATH
	var result: Dictionary = baker.call("bake", candidate)
	_assert_result_envelope(result, "terrain in runtime", failures)
	if bool(result.get("ok", false)):
		failures.append("WorldBaker accepted runtime scene containing terrain")


func _assert_invalid_terrain_does_not_replace_old_world(baker: Object, failures: Array[String]) -> void:
	var old_world: Resource = _make_world("stable_old_world", TERRAIN_SCENE_PATH, RUNTIME_SCENE_PATH)
	old_world.tags = PackedStringArray(["stable-old-content"])
	var save_error := ResourceSaver.save(old_world, WORLD_PATH)
	if save_error != OK:
		failures.append("could not reset old world fixture: %d" % save_error)
		return
	var invalid_terrain_cases: Array[String] = [
		MISSING_TERRAIN_PATH,
		BROKEN_TERRAIN_SCENE_PATH,
		WRONG_ROOT_TERRAIN_SCENE_PATH,
	]
	for invalid_terrain_path: String in invalid_terrain_cases:
		var candidate: Resource = _load_world()
		if candidate == null:
			failures.append("could not reload old world before invalid terrain test")
			continue
		(candidate.rooms[0] as Resource).terrain_scene_path = invalid_terrain_path
		var result: Dictionary = baker.call("bake", candidate)
		_assert_result_envelope(result, "invalid terrain %s" % invalid_terrain_path, failures)
		if bool(result.get("ok", false)):
			failures.append("WorldBaker accepted invalid terrain: %s" % invalid_terrain_path)
		var reloaded: Resource = _load_world()
		if reloaded == null:
			failures.append("old world disappeared after invalid terrain: %s" % invalid_terrain_path)
		elif reloaded.world_id != "stable_old_world" or reloaded.tags != PackedStringArray(["stable-old-content"]):
			failures.append("invalid terrain changed the saved world: %s" % invalid_terrain_path)


func _assert_failed_world_promotion_restores_old_file(failures: Array[String]) -> void:
	var old_world: Resource = _make_world("transaction_old_world", TERRAIN_SCENE_PATH, RUNTIME_SCENE_PATH)
	old_world.tags = PackedStringArray(["keep-me"])
	if ResourceSaver.save(old_world, WORLD_PATH) != OK:
		failures.append("could not save transactional old world fixture")
		return
	var candidate := _load_world()
	candidate.world_id = "transaction_new_world"
	candidate.tags = PackedStringArray(["replace-me"])
	var result: Dictionary = FailingPromoteBaker.new().bake(candidate)
	if bool(result.get("ok", false)):
		failures.append("WorldBaker accepted a failed staged-world promotion")
	var reloaded := _load_world()
	if reloaded == null or reloaded.world_id != "transaction_old_world" or reloaded.tags != PackedStringArray(["keep-me"]):
		failures.append("failed world promotion did not restore the previous file")
	for path: String in [_marked_world_path(".stage"), _marked_world_path(".backup")]:
		if FileAccess.file_exists(path):
			failures.append("failed world promotion retained temporary file: %s" % path)


func _assert_result_envelope(result: Dictionary, label: String, failures: Array[String]) -> void:
	if not result.has_all(["ok", "errors", "warnings"]):
		failures.append("%s result missing ok/errors/warnings: %s" % [label, str(result)])


func _make_world(world_id: String, terrain_path: String, runtime_path: String) -> Resource:
	var room: Resource = ROOM_DATA.new()
	room.room_id = "room_a"
	room.display_name = "Room A"
	room.source_scene_path = SOURCE_SCENE_PATH
	room.scene_path = runtime_path
	room.terrain_scene_path = terrain_path
	room.spawn_ids = PackedStringArray(["spawn_main"])
	room.room_size_chunks = Vector2i.ONE
	var world: Resource = WORLD_DATA.new()
	world.world_id = world_id
	world.start_room_id = "room_a"
	world.start_spawn_id = "spawn_main"
	world.rooms.assign([room])
	return world


func _load_world() -> Resource:
	return ResourceLoader.load(WORLD_PATH, "WorldData", ResourceLoader.CACHE_MODE_IGNORE) as Resource


func _save_fixtures() -> Error:
	var result := _save_source_fixture()
	if result != OK:
		return result
	result = _save_runtime_fixture(RUNTIME_SCENE_PATH, false)
	if result != OK:
		return result
	result = _save_runtime_fixture(PREVIEW_RUNTIME_SCENE_PATH, true)
	if result != OK:
		return result
	result = _save_runtime_with_terrain_fixture()
	if result != OK:
		return result
	result = _save_terrain_fixture(TERRAIN_SCENE_PATH, true)
	if result != OK:
		return result
	result = _save_terrain_fixture(BROKEN_TERRAIN_SCENE_PATH, false)
	if result != OK:
		return result
	result = _save_wrong_root_terrain_fixture()
	if result != OK:
		return result
	var wrong_resource := Resource.new()
	return ResourceSaver.save(wrong_resource, WRONG_RESOURCE_PATH)


func _save_source_fixture() -> Error:
	var root: Node2D = ROOM_AUTHORING_ROOT.new() as Node2D
	root.name = "SourceRoom"
	root.set("room_id", "room_a")
	var content := Node2D.new()
	content.name = "RoomContent"
	root.add_child(content)
	content.owner = root
	for child_name: String in ["Background", "Terrain", "Entities", "Foreground"]:
		var child := Node2D.new()
		child.name = child_name
		content.add_child(child)
		child.owner = root
	var terrain: Node = content.get_node("Terrain")
	for layer_name: String in TERRAIN_LAYER_NAMES:
		var layer := TileMapLayer.new()
		layer.name = layer_name
		terrain.add_child(layer)
		layer.owner = root
	var preview_spawn := SpawnPoint.new()
	preview_spawn.name = "DefaultSpawn"
	preview_spawn.spawn_id = "default"
	content.get_node("Entities").add_child(preview_spawn)
	preview_spawn.owner = root
	var preview := Node2D.new()
	preview.name = "PreviewOnly"
	root.add_child(preview)
	preview.owner = root
	return _save_packed_scene(root, SOURCE_SCENE_PATH)


func _save_runtime_fixture(path: String, include_preview: bool) -> Error:
	var root := Node2D.new()
	root.name = "RuntimeRoom"
	for child_name: String in ["Entities", "Foreground"]:
		var child := Node2D.new()
		child.name = child_name
		root.add_child(child)
		child.owner = root
	if include_preview:
		var preview := Node2D.new()
		preview.name = "PreviewOnly"
		root.add_child(preview)
		preview.owner = root
	return _save_packed_scene(root, path)


func _save_runtime_with_terrain_fixture() -> Error:
	var root := Node2D.new()
	root.name = "RuntimeRoomWithTerrain"
	for child_name: String in ["Entities", "Foreground", "Terrain"]:
		var child := Node2D.new()
		child.name = child_name
		root.add_child(child)
		child.owner = root
	return _save_packed_scene(root, TERRAIN_RUNTIME_SCENE_PATH)


func _save_terrain_fixture(path: String, complete: bool) -> Error:
	var root := Node2D.new()
	root.name = "TerrainRoom"
	var background := Node2D.new()
	background.name = "Background"
	root.add_child(background)
	background.owner = root
	var terrain := Node2D.new()
	terrain.name = "Terrain"
	root.add_child(terrain)
	terrain.owner = root
	var layer_count := TERRAIN_LAYER_NAMES.size() if complete else TERRAIN_LAYER_NAMES.size() - 1
	for index: int in layer_count:
		var layer := TileMapLayer.new()
		layer.name = TERRAIN_LAYER_NAMES[index]
		terrain.add_child(layer)
		layer.owner = root
	return _save_packed_scene(root, path)


func _save_wrong_root_terrain_fixture() -> Error:
	var root := Node.new()
	root.name = "WrongRootTerrain"
	var background := Node2D.new()
	background.name = "Background"
	root.add_child(background)
	background.owner = root
	var terrain := Node2D.new()
	terrain.name = "Terrain"
	root.add_child(terrain)
	terrain.owner = root
	for layer_name: String in TERRAIN_LAYER_NAMES:
		var layer := TileMapLayer.new()
		layer.name = layer_name
		terrain.add_child(layer)
		layer.owner = root
	return _save_packed_scene(root, WRONG_ROOT_TERRAIN_SCENE_PATH)


func _save_packed_scene(root: Node, path: String) -> Error:
	var packed := PackedScene.new()
	var pack_error := packed.pack(root)
	root.free()
	if pack_error != OK:
		return pack_error
	return ResourceSaver.save(packed, path)


func _remove_user_files() -> void:
	for path: String in [
		WORLD_PATH, SOURCE_SCENE_PATH, RUNTIME_SCENE_PATH, PREVIEW_RUNTIME_SCENE_PATH,
		TERRAIN_RUNTIME_SCENE_PATH, TERRAIN_SCENE_PATH, BROKEN_TERRAIN_SCENE_PATH,
		WRONG_ROOT_TERRAIN_SCENE_PATH, WRONG_RESOURCE_PATH, MISSING_TERRAIN_PATH,
		_marked_world_path(".stage"), _marked_world_path(".backup"),
	]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _marked_world_path(marker: String) -> String:
	return "%s%s.tres" % [WORLD_PATH.trim_suffix(".tres"), marker]
