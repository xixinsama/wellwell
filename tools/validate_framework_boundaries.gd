class_name FrameworkBoundaryValidator
extends RefCounted

const DEFAULT_FRAMEWORK_ROOT := "res://addons/platformer_kit"
const SCANNED_EXTENSIONS := ["gd", "tscn", "tres"]
const FORBIDDEN_PREFIXES := ["res://game/"]


func validate(framework_root: String = DEFAULT_FRAMEWORK_ROOT) -> Array[String]:
	var errors: Array[String] = []
	_scan_directory(framework_root.trim_suffix("/"), errors)
	errors.sort()
	return errors


func _scan_directory(path: String, errors: Array[String]) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		return
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if entry != "." and entry != "..":
			var entry_path := path.path_join(entry)
			if directory.current_is_dir():
				_scan_directory(entry_path, errors)
			elif SCANNED_EXTENSIONS.has(entry.get_extension().to_lower()):
				_validate_file(entry_path, errors)
		entry = directory.get_next()
	directory.list_dir_end()


func _validate_file(path: String, errors: Array[String]) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		errors.append("could not read framework source: %s" % path)
		return
	var lines := file.get_as_text().split("\n")
	for line_index: int in lines.size():
		var line := String(lines[line_index]).strip_edges()
		if line.begins_with("#") or line.begins_with(";"):
			continue
		for prefix: String in FORBIDDEN_PREFIXES:
			if line.contains(prefix):
				errors.append("%s:%d references forbidden target %s" % [path, line_index + 1, prefix])
