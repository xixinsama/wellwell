extends Node

const IMPORTER_PATH := "res://scripts/authoring/world_room_importer.gd"
const WORLD_SERVICE := preload("res://scripts/authoring/world_resource_service.gd")
const WORLD_DATA := preload("res://scripts/world/world_data.gd")
const ROOM_DATA := preload("res://scripts/world/room_data.gd")
const WORLD_PATH := "res://resources/worlds/test_import_world.tres"
const SOURCE_PATH := "res://scenes/levels/test_import_source.tscn"
const ROOM_ID := "test_import_room"
const OUTPUTS := {
	"room_resource_path": "res://resources/rooms/generated/test_import_room_room.tres",
	"runtime_scene_path": "res://scenes/rooms/generated/test_import_room_runtime.tscn",
	"terrain_scene_path": "res://scenes/rooms/generated/test_import_room_terrain.tscn",
}


class FakeRoomBaker:
	var fail_stage := false
	var fail_save := false
	var save_count := 0

	func stage(source_root: Node, source_path: String) -> Dictionary:
		if fail_stage or source_root.has_meta("invalid"):
			return _failure("invalid room source")
		var room := ROOM_DATA.new() as Resource
		room.room_id = ROOM_ID
		room.display_name = "Imported Room"
		room.source_scene_path = source_path
		room.scene_path = OUTPUTS["runtime_scene_path"]
		room.terrain_scene_path = OUTPUTS["terrain_scene_path"]
		room.spawn_ids = PackedStringArray(["alpha", "preview_z"])
		return {
			"ok": true,
			"errors": [],
			"warnings": [],
			"room_data": room,
			"manifest": {"room_id": ROOM_ID, "preview_spawn_id": "preview_z"},
			"outputs": OUTPUTS.duplicate(),
		}

	func save_staged(staged: Dictionary) -> Dictionary:
		save_count += 1
		if fail_save:
			return _failure("forced room save failure")
		for path: String in OUTPUTS.values():
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
		if ResourceSaver.save(_make_scene("ImportedRuntime"), OUTPUTS["runtime_scene_path"]) != OK:
			return _failure("could not save fake runtime scene")
		if ResourceSaver.save(_make_scene("ImportedTerrain"), OUTPUTS["terrain_scene_path"]) != OK:
			return _failure("could not save fake terrain scene")
		if ResourceSaver.save(staged["room_data"], OUTPUTS["room_resource_path"]) != OK:
			return _failure("could not save fake RoomData")
		return {
			"ok": true,
			"errors": [],
			"warnings": [],
			"outputs": OUTPUTS.duplicate(),
		}

	func _make_scene(root_name: String) -> PackedScene:
		var root := Node2D.new()
		root.name = root_name
		var packed := PackedScene.new()
		packed.pack(root)
		root.free()
		return packed

	func _failure(message: String) -> Dictionary:
		return {"ok": false, "errors": [message], "warnings": []}


class FakeWorldStore:
	var fail_next_save := false
	var service: Object = WORLD_SERVICE.new()

	func save_candidate(world: Resource, path: String) -> Dictionary:
		if fail_next_save:
			fail_next_save = false
			return {
				"ok": false,
				"errors": ["forced world save failure"],
				"warnings": [],
				"world": null,
				"path": path,
			}
		return service.call("save_candidate", world, path)


func run() -> Array[String]:
	_cleanup()
	if not FileAccess.file_exists(IMPORTER_PATH):
		return ["missing production API: %s" % IMPORTER_PATH]
	var importer_script := load(IMPORTER_PATH) as Script
	if importer_script == null or not importer_script.can_instantiate():
		return ["WorldRoomImporter could not be loaded"]
	var failures: Array[String] = []
	_assert_preconditions(importer_script, failures)
	_assert_successful_first_room_import(importer_script, failures)
	_assert_successful_later_room_import_uses_unplaced_origin(importer_script, failures)
	_assert_duplicate_rejected_before_writes(importer_script, failures)
	_assert_missing_start_rejected(importer_script, failures)
	_assert_room_save_failure_rolls_back(importer_script, failures)
	_assert_world_save_failure_restores_orphans(importer_script, failures)
	_cleanup()
	return failures


func _assert_preconditions(importer_script: Script, failures: Array[String]) -> void:
	var importer: Object = importer_script.new()
	var baker := FakeRoomBaker.new()
	importer.call("set_room_baker_adapter", baker)
	var source := Node.new()
	if bool(importer.call("import_room", null, source, SOURCE_PATH).get("ok", false)):
		failures.append("room importer accepted null WorldData")
	var unsaved := WORLD_DATA.new() as Resource
	if bool(importer.call("import_room", unsaved, source, SOURCE_PATH).get("ok", false)):
		failures.append("room importer accepted unsaved WorldData")
	var world := _save_and_load_world(_make_world(false), failures)
	if world != null and bool(importer.call("import_room", world, source, "user://bad.tscn").get("ok", false)):
		failures.append("room importer accepted a non-res source path")
	if world != null:
		source.set_meta("invalid", true)
		if bool(importer.call("import_room", world, source, SOURCE_PATH).get("ok", false)):
			failures.append("room importer accepted a source rejected during staging")
	if baker.save_count != 0:
		failures.append("room importer wrote outputs while rejecting preconditions")
	source.free()
	_cleanup()


func _assert_successful_first_room_import(importer_script: Script, failures: Array[String]) -> void:
	var world := _save_and_load_world(_make_world(false), failures)
	if world == null:
		return
	var importer: Object = importer_script.new()
	importer.call("set_room_baker_adapter", FakeRoomBaker.new())
	var source := Node.new()
	var result: Dictionary = importer.call("import_room", world, source, SOURCE_PATH)
	source.free()
	_assert_envelope(result, "successful import", failures)
	if not bool(result.get("ok", false)):
		failures.append("valid first-room import failed: %s" % str(result.get("errors", [])))
		_cleanup()
		return
	var saved_world := result.get("world") as Resource
	var imported_room := result.get("room") as Resource
	if saved_world == null or imported_room == null or not saved_world.has_room(ROOM_ID):
		failures.append("successful import did not return the saved world and room")
	else:
		if saved_world.start_room_id != ROOM_ID or saved_world.start_spawn_id != "preview_z":
			failures.append("first imported room did not use manifest preview_spawn_id as world start")
		if saved_world.call("get_room_origin_chunk", ROOM_ID) != Vector2i.ZERO:
			failures.append("first imported room did not default to world origin (0, 0)")
		if saved_world.get_room(ROOM_ID).resource_path != OUTPUTS["room_resource_path"]:
			failures.append("saved world does not reference the final generated RoomData")
	var result_outputs: Dictionary = result.get("outputs", {})
	if result_outputs.get("world_resource_path") != WORLD_PATH:
		failures.append("import result omitted the final WorldData path")
	for key: String in OUTPUTS:
		if result_outputs.get(key) != OUTPUTS[key] or not FileAccess.file_exists(OUTPUTS[key]):
			failures.append("import result omitted generated output: %s" % key)
	if not result.has_all(["before_state", "after_state", "source_path"]):
		failures.append("import result omitted undo states or source path")
	_assert_no_import_backups(failures)
	_cleanup()


func _assert_successful_later_room_import_uses_unplaced_origin(importer_script: Script, failures: Array[String]) -> void:
	var world_data := _make_world(true)
	var world := _save_and_load_world(world_data, failures)
	if world == null:
		return
	var importer: Object = importer_script.new()
	importer.call("set_room_baker_adapter", FakeRoomBaker.new())
	var source := Node.new()
	var result: Dictionary = importer.call("import_room", world, source, SOURCE_PATH)
	source.free()
	if not bool(result.get("ok", false)):
		failures.append("valid later-room import failed: %s" % str(result.get("errors", [])))
		_cleanup()
		return
	var saved_world := result.get("world") as Resource
	if saved_world.call("get_room_origin_chunk", ROOM_ID) != Vector2i(-1, -1):
		failures.append("later imported room did not default to unplaced origin (-1, -1)")
	_cleanup()


func _assert_duplicate_rejected_before_writes(importer_script: Script, failures: Array[String]) -> void:
	var world_data := _make_world(true)
	var duplicate := _make_room(ROOM_ID)
	world_data.rooms.append(duplicate)
	var world := _save_and_load_world(world_data, failures)
	if world == null:
		return
	var baker := FakeRoomBaker.new()
	var importer: Object = importer_script.new()
	importer.call("set_room_baker_adapter", baker)
	var source := Node.new()
	var result: Dictionary = importer.call("import_room", world, source, SOURCE_PATH)
	source.free()
	if bool(result.get("ok", false)):
		failures.append("room importer accepted duplicate room_id")
	if baker.save_count != 0:
		failures.append("duplicate room_id was rejected after writing outputs")
	_cleanup()


func _assert_missing_start_rejected(importer_script: Script, failures: Array[String]) -> void:
	var world_data := _make_world(false)
	world_data.rooms.append(_make_room("existing_room"))
	var world := _save_and_load_world(world_data, failures)
	if world == null:
		return
	var baker := FakeRoomBaker.new()
	var importer: Object = importer_script.new()
	importer.call("set_room_baker_adapter", baker)
	var source := Node.new()
	var result: Dictionary = importer.call("import_room", world, source, SOURCE_PATH)
	source.free()
	if bool(result.get("ok", false)):
		failures.append("room importer accepted a non-empty world without a start endpoint")
	if baker.save_count != 0:
		failures.append("missing world start was rejected after writing outputs")
	_cleanup()


func _assert_room_save_failure_rolls_back(importer_script: Script, failures: Array[String]) -> void:
	var world := _save_and_load_world(_make_world(false), failures)
	if world == null:
		return
	var old_world_bytes := FileAccess.get_file_as_bytes(WORLD_PATH)
	var baker := FakeRoomBaker.new()
	baker.fail_save = true
	var importer: Object = importer_script.new()
	importer.call("set_room_baker_adapter", baker)
	var source := Node.new()
	var result: Dictionary = importer.call("import_room", world, source, SOURCE_PATH)
	source.free()
	if bool(result.get("ok", false)):
		failures.append("room importer accepted a forced room save failure")
	if FileAccess.get_file_as_bytes(WORLD_PATH) != old_world_bytes:
		failures.append("room save failure changed the existing WorldData file")
	for path: String in OUTPUTS.values():
		if FileAccess.file_exists(path):
			failures.append("room save failure retained newly created final: %s" % path)
	_assert_no_import_backups(failures)
	_cleanup()


func _assert_world_save_failure_restores_orphans(importer_script: Script, failures: Array[String]) -> void:
	var world := _save_and_load_world(_make_world(false), failures)
	if world == null or not _seed_orphan_outputs(failures):
		return
	var before := _read_final_bytes()
	var world_store := FakeWorldStore.new()
	world_store.fail_next_save = true
	var importer: Object = importer_script.new()
	importer.call("set_room_baker_adapter", FakeRoomBaker.new())
	importer.call("set_world_resources_adapter", world_store)
	var source := Node.new()
	var result: Dictionary = importer.call("import_room", world, source, SOURCE_PATH)
	source.free()
	if bool(result.get("ok", false)):
		failures.append("room importer accepted a forced world save failure")
	if _read_final_bytes() != before:
		failures.append("failed world save did not restore all room and world files")
	_assert_no_import_backups(failures)
	_cleanup()


func _make_world(with_start: bool) -> Resource:
	var world := WORLD_DATA.new() as Resource
	world.world_id = "test_import_world"
	if with_start:
		var start_room := _make_room("start_room")
		world.rooms.append(start_room)
		world.start_room_id = start_room.room_id
		world.start_spawn_id = "start"
	return world


func _make_room(room_id: String) -> Resource:
	var room := ROOM_DATA.new() as Resource
	room.room_id = room_id
	room.spawn_ids = PackedStringArray(["start"])
	return room


func _save_and_load_world(world: Resource, failures: Array[String]) -> Resource:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(WORLD_PATH.get_base_dir()))
	if ResourceSaver.save(world, WORLD_PATH) != OK:
		failures.append("could not save importer WorldData fixture")
		return null
	return ResourceLoader.load(WORLD_PATH, "WorldData", ResourceLoader.CACHE_MODE_IGNORE) as Resource


func _seed_orphan_outputs(failures: Array[String]) -> bool:
	var baker := FakeRoomBaker.new()
	var old_room := _make_room("old_orphan")
	old_room.tags = PackedStringArray(["preserve-old-bytes"])
	for path: String in OUTPUTS.values():
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	if ResourceSaver.save(baker._make_scene("OldRuntime"), OUTPUTS["runtime_scene_path"]) != OK \
		or ResourceSaver.save(baker._make_scene("OldTerrain"), OUTPUTS["terrain_scene_path"]) != OK \
		or ResourceSaver.save(old_room, OUTPUTS["room_resource_path"]) != OK:
		failures.append("could not seed orphan room outputs")
		return false
	return true


func _read_final_bytes() -> Dictionary:
	var result: Dictionary = {WORLD_PATH: FileAccess.get_file_as_bytes(WORLD_PATH)}
	for path: String in OUTPUTS.values():
		result[path] = FileAccess.get_file_as_bytes(path)
	return result


func _assert_envelope(result: Dictionary, label: String, failures: Array[String]) -> void:
	if not result.has_all(["ok", "errors", "warnings", "world", "room", "path", "outputs"]):
		failures.append("%s result is missing the importer envelope: %s" % [label, str(result)])


func _assert_no_import_backups(failures: Array[String]) -> void:
	for path: String in [WORLD_PATH] + Array(OUTPUTS.values()):
		var backup := _marked_path(path, ".import_backup")
		if FileAccess.file_exists(backup):
			failures.append("room import retained outer backup: %s" % backup)


func _cleanup() -> void:
	for path: String in [WORLD_PATH] + Array(OUTPUTS.values()):
		for candidate: String in [
			path,
			_marked_path(path, ".stage"),
			_marked_path(path, ".backup"),
			_marked_path(path, ".import_backup"),
		]:
			if FileAccess.file_exists(candidate):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(candidate))


func _marked_path(path: String, marker: String) -> String:
	var extension_start := path.rfind(".")
	return "%s%s%s" % [path.left(extension_start), marker, path.substr(extension_start)]
