class_name InputMappingStore
extends RefCounted

const SCHEMA_VERSION := 1


func load_overrides(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": true, "missing": true, "actions": {}}
	var config := ConfigFile.new()
	var error := config.load(path)
	if error != OK:
		return {"ok": false, "missing": false, "actions": {}, "error": error}
	if int(config.get_value("meta", "schema_version", -1)) != SCHEMA_VERSION:
		return {"ok": false, "missing": false, "actions": {}, "error": ERR_INVALID_DATA}
	var actions: Variant = config.get_value("actions", "overrides", {})
	if not actions is Dictionary:
		return {"ok": false, "missing": false, "actions": {}, "error": ERR_INVALID_DATA}
	return {"ok": true, "missing": false, "actions": actions}


func save_overrides(path: String, overrides: Dictionary) -> bool:
	var config := ConfigFile.new()
	config.set_value("meta", "schema_version", SCHEMA_VERSION)
	config.set_value("actions", "overrides", overrides)
	return config.save(path) == OK


func clear_overrides(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return true
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK
