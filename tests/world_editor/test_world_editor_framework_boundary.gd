extends Node

const EDITOR_ROOT := "res://addons/world_editor"
const FRAMEWORK_ROOT := "res://addons/platformer_kit"


func run() -> Array[String]:
	var failures: Array[String] = []
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(EDITOR_ROOT)):
		failures.append("World Editor has not moved to addons/world_editor")
		return failures
	var project_source := FileAccess.get_file_as_string("res://project.godot")
	if project_source.contains("addons/wellwell_world_editor"):
		failures.append("project settings still enable the legacy World Editor path")
	var config := ConfigFile.new()
	if config.load(EDITOR_ROOT + "/plugin.cfg") != OK:
		failures.append("World Editor manifest could not be loaded")
	elif String(config.get_value("plugin", "name", "")) != "World Editor":
		failures.append("World Editor manifest retains a project-specific name")
	for path: String in _collect_source_files(EDITOR_ROOT):
		var source := FileAccess.get_file_as_string(path)
		for line: String in source.split("\n"):
			for forbidden: String in ["res://scripts/", "res://game/"]:
				if line.contains("preload(") and line.contains(forbidden):
					failures.append("World Editor dependency escapes addon/framework boundary: %s -> %s" % [path, forbidden])
			if line.contains("res://addons/platformer_kit/") and not line.contains("res://addons/platformer_kit/world/"):
				failures.append("World Editor depends on a non-world framework module: %s" % path)
		if source.contains("TEMPLATE_SCENE_PATH"):
			failures.append("World Editor hard-codes a concrete room template: %s" % path)
	for path: String in _collect_source_files(FRAMEWORK_ROOT):
		if FileAccess.get_file_as_string(path).contains("res://addons/world_editor"):
			failures.append("runtime framework depends on World Editor: %s" % path)
	return failures


func _collect_source_files(root: String) -> Array[String]:
	var result: Array[String] = []
	_collect_recursive(root, result)
	return result


func _collect_recursive(path: String, result: Array[String]) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		return
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		var child := path.path_join(entry)
		if directory.current_is_dir():
			_collect_recursive(child, result)
		elif entry.get_extension().to_lower() in ["gd", "tscn", "cfg"]:
			result.append(child)
		entry = directory.get_next()
	directory.list_dir_end()
