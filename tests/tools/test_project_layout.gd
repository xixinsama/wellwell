extends Node

## Keeps the directory contract enforced after moves:
## - GDScript lives under game/, addons/, tests/ or tools/ — never under scenes/,
##   resources/ or examples/.
## - The retired scripts root never comes back in a scene, resource or
##   script path.

const SCRIPT_ROOTS: Array[String] = ["game", "addons", "tests", "tools", "examples"]
const FORBIDDEN_SCRIPT_DIRS: Array[String] = ["scenes", "resources", "assets"]
const RETIRED_PREFIX := "res://" + "scripts/"


func run() -> Array[String]:
	var failures: Array[String] = []
	for directory: String in FORBIDDEN_SCRIPT_DIRS:
		for path: String in _files(directory, ".gd"):
			failures.append("script outside game/addons/tests/tools: %s" % path)
	for root: String in ["scenes", "resources", "game", "addons", "tests", "examples", "tools"]:
		for path: String in _files(root, ".tscn") + _files(root, ".tres") + _files(root, ".gd"):
			var source := FileAccess.get_file_as_string(path)
			if source.contains(RETIRED_PREFIX):
				failures.append("retired %s path in: %s" % [RETIRED_PREFIX, path])
	return failures


func _files(root: String, extension: String) -> Array[String]:
	var files: Array[String] = []
	var directory := DirAccess.open("res://" + root)
	if directory == null:
		return files
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if entry != "." and entry != "..":
			var path := "res://%s/%s" % [root, entry]
			if directory.current_is_dir():
				files.append_array(_files("%s/%s" % [root, entry], extension))
			elif entry.ends_with(extension):
				files.append(path)
		entry = directory.get_next()
	directory.list_dir_end()
	files.sort()
	return files
