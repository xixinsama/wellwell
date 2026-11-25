class_name GlobalSettingsStore
extends RefCounted

var path := "user://settings.json"


func _init(new_path: String = "user://settings.json") -> void:
	path = new_path


func save(settings: Dictionary) -> bool:
	var merged := load_settings()
	merged.merge(settings, true)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(merged, "  ", false))
	file.close()
	return true


func load_settings() -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var json := JSON.new()
	var text := file.get_as_text()
	file.close()
	if json.parse(text) != OK or not json.data is Dictionary:
		return {}
	return json.data
