extends Node

## Coverage for the World editor room status service: fresh, stale, missing
## artifacts/source, session bake failures, unknown fingerprints and the source
## hash cache.

const STATUS := preload("res://addons/world_editor/authoring/world/room_status_service.gd")
const ROOM_DATA := preload("res://addons/platformer_kit/world/data/room_data.gd")

const SOURCE := "user://world_status_source.tscn"
const RUNTIME := "user://world_status_runtime.tscn"
const TERRAIN := "user://world_status_terrain.tscn"
const ROOM_ID := "room_status_test"


func run() -> Array[String]:
	var failures: Array[String] = []
	_write_fixtures()
	_assert_fresh(failures)
	_assert_stale(failures)
	_assert_unknown_without_fingerprint(failures)
	_assert_unknown_without_source(failures)
	_assert_error_missing_source(failures)
	_assert_error_missing_artifact(failures)
	_assert_error_bake_failure(failures)
	_assert_hash_cache(failures)
	_cleanup()
	return failures


func _assert_fresh(failures: Array[String]) -> void:
	var service := STATUS.new() as RoomStatusService
	var status := service.evaluate(_make_room())
	if status["state"] != RoomStatusService.FRESH:
		failures.append("fresh room was not reported fresh: %s" % status.get("state", ""))


func _assert_stale(failures: Array[String]) -> void:
	var service := STATUS.new() as RoomStatusService
	var status := service.evaluate(_make_room("deadbeef"))
	if status["state"] != RoomStatusService.STALE:
		failures.append("changed source was not reported stale: %s" % status.get("state", ""))


func _assert_unknown_without_fingerprint(failures: Array[String]) -> void:
	var service := STATUS.new() as RoomStatusService
	var room := _make_room()
	room.source_fingerprint = ""
	if service.evaluate(room)["state"] != RoomStatusService.UNKNOWN:
		failures.append("room without a fingerprint was not unknown")


func _assert_unknown_without_source(failures: Array[String]) -> void:
	var service := STATUS.new() as RoomStatusService
	var room := _make_room()
	room.source_scene_path = ""
	if service.evaluate(room)["state"] != RoomStatusService.UNKNOWN:
		failures.append("room without a source path was not unknown")


func _assert_error_missing_source(failures: Array[String]) -> void:
	var service := STATUS.new() as RoomStatusService
	var room := _make_room()
	room.source_scene_path = "user://world_status_missing_source.tscn"
	if service.evaluate(room)["state"] != RoomStatusService.ERROR:
		failures.append("missing source scene was not reported as an error")


func _assert_error_missing_artifact(failures: Array[String]) -> void:
	var service := STATUS.new() as RoomStatusService
	var room := _make_room()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(RUNTIME))
	var status := service.evaluate(room)
	if status["state"] != RoomStatusService.ERROR:
		failures.append("missing runtime scene was not reported as an error")
	_write(RUNTIME, "[gd_scene format=3]\n")
	service.clear_cache()
	if service.evaluate(room)["state"] != RoomStatusService.FRESH:
		failures.append("restored runtime scene did not return to fresh")


func _assert_error_bake_failure(failures: Array[String]) -> void:
	var service := STATUS.new() as RoomStatusService
	var room := _make_room()
	service.mark_bake_failure(ROOM_ID, "bake exploded")
	var status := service.evaluate(room)
	if status["state"] != RoomStatusService.ERROR or not String(status["message"]).contains("bake exploded"):
		failures.append("session bake failure was not reported with its message")
	service.clear_bake_failure(ROOM_ID)
	if service.evaluate(room)["state"] != RoomStatusService.FRESH:
		failures.append("cleared bake failure did not return to fresh")


func _assert_hash_cache(failures: Array[String]) -> void:
	var service := STATUS.new() as RoomStatusService
	var calls := [0]
	service.hash_provider = func(path: String) -> String:
		calls[0] += 1
		return FileAccess.get_sha256(path)
	var room := _make_room()
	service.evaluate(room)
	service.evaluate(room)
	if int(calls[0]) != 1:
		failures.append("source hash was recomputed for an unchanged file (%d calls)" % int(calls[0]))
	# A content change with a different size invalidates the cache and the state.
	_write(SOURCE, "[gd_scene format=3]\n\n[node name=\"Changed\" type=\"Node2D\"]\n")
	service.evaluate(room)
	if int(calls[0]) != 2:
		failures.append("source hash was not recomputed after the file changed (%d calls)" % int(calls[0]))
	if service.evaluate(room)["state"] != RoomStatusService.STALE:
		failures.append("rewritten source did not become stale")
	service.evaluate(room)
	if int(calls[0]) != 2:
		failures.append("hash cache did not hit after re-reading the changed file")


func _make_room(fingerprint := "") -> RoomData:
	var room := ROOM_DATA.new() as RoomData
	room.room_id = ROOM_ID
	room.source_scene_path = SOURCE
	room.source_fingerprint = fingerprint if not fingerprint.is_empty() else FileAccess.get_sha256(SOURCE)
	room.scene_path = RUNTIME
	room.terrain_scene_path = TERRAIN
	return room


func _write_fixtures() -> void:
	_write(SOURCE, "[gd_scene format=3]\n\n[node name=\"Source\" type=\"Node2D\"]\n")
	_write(RUNTIME, "[gd_scene format=3]\n\n[node name=\"Runtime\" type=\"Node2D\"]\n")
	_write(TERRAIN, "[gd_scene format=3]\n\n[node name=\"Terrain\" type=\"Node2D\"]\n")


func _write(path: String, content: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(content)
	file.close()


func _cleanup() -> void:
	for path in [SOURCE, RUNTIME, TERRAIN]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
