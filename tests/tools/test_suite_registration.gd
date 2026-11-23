extends Node

## Every `test_*.gd` under `tests/` must be registered in the runtime suite, and
## every suite entry must exist. Silent test loss is the most expensive kind of
## cleanup regression.

const SUITE_PATH := "res://tests/runtime_suite.gd"
const TESTS_ROOT := "res://tests"


func run() -> Array[String]:
	var failures: Array[String] = []
	var source := FileAccess.get_file_as_string(SUITE_PATH)
	if source.is_empty():
		return ["runtime suite script is missing or empty: %s" % SUITE_PATH]
	var registered := _registered_paths(source)
	if registered.is_empty():
		return ["runtime suite does not preload any test"]
	for path: String in registered:
		if not FileAccess.file_exists(path):
			failures.append("runtime suite lists a missing test: %s" % path)
	var on_disk := _test_files(TESTS_ROOT)
	for path: String in on_disk:
		if not registered.has(path):
			failures.append("test file is not registered in runtime_suite.gd: %s" % path)
	return failures


func _registered_paths(source: String) -> Dictionary:
	var paths := {}
	var regex := RegEx.new()
	regex.compile("preload\\(\"(res://tests/[^\"]+\\.gd)\"\\)")
	for result: RegExMatch in regex.search_all(source):
		paths[result.get_string(1)] = true
	return paths


func _test_files(path: String) -> Array[String]:
	var files: Array[String] = []
	var directory := DirAccess.open(path)
	if directory == null:
		return files
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if entry != "." and entry != "..":
			var entry_path := path.path_join(entry)
			if directory.current_is_dir():
				files.append_array(_test_files(entry_path))
			elif entry.begins_with("test_") and entry.ends_with(".gd"):
				files.append(entry_path)
		entry = directory.get_next()
	directory.list_dir_end()
	files.sort()
	return files
