extends Node

const ROOM_BAKE_PATHS: Script = preload("res://scripts/authoring/room_bake_paths.gd")
const ROOM_BAKE_MANIFEST: Script = preload("res://scripts/authoring/room_bake_manifest.gd")
const ROOM_DATA: Script = preload("res://scripts/world/room_data.gd")
const ROOM_AUTHORING_ROOT: Script = preload("res://scripts/authoring/room_authoring_root.gd")
const ROOM_ENTRANCE: Script = preload("res://scripts/world/room_entrance.gd")
const SPAWN_POINT: Script = preload("res://scripts/world/spawn_point.gd")
const WORLD_ENTITY: Script = preload("res://scripts/world/world_entity.gd")


func run() -> Array[String]:
	var failures: Array[String] = []
	_assert_sanitizes_room_ids(failures)
	_assert_generates_deterministic_paths(failures)
	_assert_rejects_invalid_manifest_inputs(failures)
	_assert_normalizes_authoring_manifest(failures)
	_assert_sorts_and_deduplicates_manifest_arrays(failures)
	_assert_applies_metadata_without_overwriting_world_fields(failures)
	return failures


func _assert_sanitizes_room_ids(failures: Array[String]) -> void:
	if ROOM_BAKE_PATHS.sanitize_room_id(" Level 0 ") != "level_0":
		failures.append("room id whitespace or case was not normalized")
	if ROOM_BAKE_PATHS.sanitize_room_id("Boss---Room 2") != "boss_room_2":
		failures.append("invalid room id runs were not collapsed")
	if ROOM_BAKE_PATHS.sanitize_room_id("___level___") != "level":
		failures.append("leading and trailing underscores were not fully trimmed")
	if ROOM_BAKE_PATHS.sanitize_room_id(" !@#$ ") != "":
		failures.append("room id with no valid characters was not emptied")


func _assert_generates_deterministic_paths(failures: Array[String]) -> void:
	var paths: Dictionary = ROOM_BAKE_PATHS.for_room_id("Level 0")
	var expected := {
		"room_id": "level_0",
		"runtime_scene_path": "res://scenes/rooms/generated/level_0_runtime.tscn",
		"terrain_scene_path": "res://scenes/rooms/generated/level_0_terrain.tscn",
		"room_resource_path": "res://resources/rooms/generated/level_0_room.tres",
	}
	if paths != expected:
		failures.append("generated paths did not match the deterministic contract")
	if paths["runtime_scene_path"] == paths["terrain_scene_path"] or paths["terrain_scene_path"] == paths["room_resource_path"]:
		failures.append("generated output paths were not distinct")


func _assert_rejects_invalid_manifest_inputs(failures: Array[String]) -> void:
	var root := Node2D.new()
	root.set_script(preload("res://scripts/authoring/room_authoring_root.gd"))
	root.set("room_id", "!!!")
	var invalid_id: Dictionary = ROOM_BAKE_MANIFEST.from_authoring_root(root, "res://scenes/levels/room.tscn")
	if not invalid_id.is_empty():
		failures.append("sanitized-empty room id was accepted")
	var valid_root := Node2D.new()
	valid_root.set_script(preload("res://scripts/authoring/room_authoring_root.gd"))
	valid_root.set("room_id", "room_a")
	if not ROOM_BAKE_MANIFEST.from_authoring_root(valid_root, "").is_empty():
		failures.append("empty source path was accepted")
	root.free()
	valid_root.free()


func _assert_normalizes_authoring_manifest(failures: Array[String]) -> void:
	var root := Node2D.new()
	root.set_script(preload("res://scripts/authoring/room_authoring_root.gd"))
	root.set("room_id", "Level 0")
	root.set("display_name", "Level Zero")
	root.set("room_size_chunks", Vector2i(2, 1))
	root.set("preview_spawn_id", "spawn_a")
	root.set("tags", PackedStringArray(["platformer", "intro", "intro"]))
	var manifest: Dictionary = ROOM_BAKE_MANIFEST.from_authoring_root(root, "res://scenes/levels/level_0.tscn")
	if manifest.get("room_id") != "level_0":
		failures.append("manifest room id was not sanitized")
	if manifest.get("source_scene_path") != "res://scenes/levels/level_0.tscn":
		failures.append("manifest source path was not recorded")
	if manifest.get("tags") != ["intro", "platformer"]:
		failures.append("manifest tags were not sorted and deduplicated")
	for key: String in ["runtime_scene_path", "terrain_scene_path", "room_resource_path"]:
		if String(manifest.get(key, "")).is_empty():
			failures.append("manifest omitted generated path: %s" % key)
	root.free()


func _assert_sorts_and_deduplicates_manifest_arrays(failures: Array[String]) -> void:
	var root: Node2D = ROOM_AUTHORING_ROOT.new()
	root.room_id = "room_a"
	var room_content := Node2D.new()
	room_content.name = "RoomContent"
	root.add_child(room_content)
	var entities := Node2D.new()
	entities.name = "Entities"
	room_content.add_child(entities)
	for entrance_id: String in ["z_exit", "a_exit", "z_exit"]:
		var entrance: Node = ROOM_ENTRANCE.new()
		entrance.entity_id = entrance_id
		entities.add_child(entrance)
	for spawn_id: String in ["spawn_z", "spawn_a", "spawn_z"]:
		var spawn: Node = SPAWN_POINT.new()
		spawn.spawn_id = spawn_id
		entities.add_child(spawn)
	for entity_id: String in ["switch_z", "switch_a", "switch_z"]:
		var entity: Node = WORLD_ENTITY.new()
		entity.entity_id = entity_id
		entity.persistent = true
		entities.add_child(entity)
	var manifest: Dictionary = ROOM_BAKE_MANIFEST.from_authoring_root(root, "res://scenes/levels/room_a.tscn")
	if manifest.get("entrance_ids") != ["a_exit", "z_exit"]:
		failures.append("entrance IDs were not sorted and deduplicated")
	if manifest.get("spawn_ids") != ["spawn_a", "spawn_z"]:
		failures.append("spawn IDs were not sorted and deduplicated")
	if manifest.get("entity_ids") != ["switch_a", "switch_z"]:
		failures.append("entity IDs were not sorted and deduplicated")
	root.free()


func _assert_applies_metadata_without_overwriting_world_fields(failures: Array[String]) -> void:
	var root := Node2D.new()
	root.set_script(preload("res://scripts/authoring/room_authoring_root.gd"))
	root.set("room_id", "Room A")
	root.set("display_name", "Room A")
	root.set("room_size_chunks", Vector2i(3, 2))
	root.set("tags", PackedStringArray(["zeta", "alpha", "zeta"]))
	var manifest: Dictionary = ROOM_BAKE_MANIFEST.from_authoring_root(root, "res://scenes/levels/room_a.tscn")
	var room: Resource = ROOM_DATA.new()
	room.scene_path = "res://scenes/rooms/legacy_runtime.tscn"
	room.tags = PackedStringArray(["stale"])
	room.room_origin_chunk = Vector2i(4, -2)
	room.adjacent_room_ids = PackedStringArray(["room_b"])
	if not ROOM_BAKE_MANIFEST.apply_to_room_data(manifest, room):
		failures.append("valid manifest was not applied to RoomData")
	if room.room_id != "room_a" or room.room_origin_chunk != Vector2i(4, -2):
		failures.append("room metadata or world placement was wrong after apply")
	if room.scene_path != "res://scenes/rooms/generated/room_a_runtime.tscn":
		failures.append("apply did not update legacy scene_path to runtime path")
	if room.tags != PackedStringArray(["alpha", "zeta"]):
		failures.append("apply did not copy normalized tags")
	if room.adjacent_room_ids != PackedStringArray(["room_b"]):
		failures.append("apply overwrote world-owned adjacent room ids")
	root.free()
