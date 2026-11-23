extends Node

const ROOM_BAKER_PATH := "res://addons/world_editor/authoring/room/room_baker.gd"
const FIXTURE_PATH := "user://room_baker_fingerprint_fixture.tscn"


func run() -> Array[String]:
	var failures: Array[String] = []
	var file := FileAccess.open(FIXTURE_PATH, FileAccess.WRITE)
	if file == null:
		return ["could not create RoomBaker fingerprint fixture"]
	file.store_string("[gd_scene format=3]\n")
	file.close()
	var baker_script := load(ROOM_BAKER_PATH) as Script
	if baker_script == null or not baker_script.can_instantiate():
		return ["RoomBaker could not be loaded"]
	var baker: RefCounted = baker_script.new() as RefCounted
	if not baker.has_method("get_source_fingerprint"):
		failures.append("RoomBaker must expose get_source_fingerprint")
	else:
		var expected := FileAccess.get_sha256(FIXTURE_PATH)
		var actual: String = baker.call("get_source_fingerprint", FIXTURE_PATH)
		if actual != expected or actual.is_empty():
			failures.append("RoomBaker source fingerprint must match the saved scene bytes")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(FIXTURE_PATH))
	return failures
