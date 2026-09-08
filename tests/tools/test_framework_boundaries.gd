extends Node

const VALIDATOR_PATH := "res://tools/validate_framework_boundaries.gd"
const FIXTURE_ROOT := "user://framework_boundary_fixture"
const FRAMEWORK_ROOT := FIXTURE_ROOT + "/addons/platformer_kit"
const GAME_ROOT := FIXTURE_ROOT + "/game"


func run() -> Array[String]:
	var failures: Array[String] = []
	_cleanup_fixture()
	if not _write_fixture_files():
		_cleanup_fixture()
		return ["could not create framework boundary fixtures"]
	if not ResourceLoader.exists(VALIDATOR_PATH, "Script"):
		_cleanup_fixture()
		return ["framework boundary validator is missing"]
	var validator_script := load(VALIDATOR_PATH) as Script
	if validator_script == null or not validator_script.can_instantiate():
		_cleanup_fixture()
		return ["framework boundary validator is missing"]
	var validator: RefCounted = validator_script.new() as RefCounted
	var errors: Array[String] = validator.call("validate", FRAMEWORK_ROOT)
	if errors.size() != 1:
		failures.append("framework boundary validator did not report exactly one forbidden dependency")
	elif not errors[0].contains("forbidden.gd") or not errors[0].contains("res://game/"):
		failures.append("framework boundary error did not identify the file and forbidden target")
	_cleanup_fixture()
	return failures


func _write_fixture_files() -> bool:
	var framework_absolute := ProjectSettings.globalize_path(FRAMEWORK_ROOT)
	var game_absolute := ProjectSettings.globalize_path(GAME_ROOT)
	if DirAccess.make_dir_recursive_absolute(framework_absolute) != OK:
		return false
	if DirAccess.make_dir_recursive_absolute(game_absolute) != OK:
		return false
	return (
		_write_text(FRAMEWORK_ROOT + "/allowed.gd", "extends RefCounted\nconst SELF = preload(\"res://addons/platformer_kit/core/example.gd\")\n")
		and _write_text(FRAMEWORK_ROOT + "/forbidden.gd", "extends RefCounted\nconst GAME = preload(\"res://game/player/player.gd\")\n")
		and _write_text(GAME_ROOT + "/allowed.gd", "extends Node\nconst KIT = preload(\"res://addons/platformer_kit/core/example.gd\")\n")
	)


func _write_text(path: String, content: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(content)
	return true


func _cleanup_fixture() -> void:
	for path: String in [
		FRAMEWORK_ROOT + "/allowed.gd",
		FRAMEWORK_ROOT + "/forbidden.gd",
		GAME_ROOT + "/allowed.gd",
	]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	for path: String in [FRAMEWORK_ROOT, FIXTURE_ROOT + "/addons", GAME_ROOT, FIXTURE_ROOT]:
		var absolute := ProjectSettings.globalize_path(path)
		if DirAccess.dir_exists_absolute(absolute):
			DirAccess.remove_absolute(absolute)
