class_name SaveStorage
extends RefCounted

const SAVE_CODEC: Script = preload("res://scripts/save/save_codec.gd")

var root_path := "user://saves"


func _init(new_root_path: String = "user://saves") -> void:
	root_path = new_root_path.trim_suffix("/")


func write_slot(snapshot: RefCounted) -> bool:
	if snapshot == null or not _valid_slot(snapshot.slot):
		return false
	if not _ensure_root():
		return false

	var primary := _slot_path(snapshot.slot)
	var temporary := primary + ".tmp"
	var backup := _backup_path(snapshot.slot)
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return false

	var codec: RefCounted = SAVE_CODEC.new()
	snapshot.saved_unix_time = int(Time.get_unix_time_from_system())
	file.store_string(codec.encode(snapshot))
	file.flush()
	file.close()

	if FileAccess.file_exists(backup):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(backup))

	if FileAccess.file_exists(primary):
		var backup_error := DirAccess.rename_absolute(
			ProjectSettings.globalize_path(primary),
			ProjectSettings.globalize_path(backup)
		)
		if backup_error != OK:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
			return false

	var promote_error := DirAccess.rename_absolute(
		ProjectSettings.globalize_path(temporary),
		ProjectSettings.globalize_path(primary)
	)
	if promote_error != OK:
		return false

	return read_slot(snapshot.slot) != null


func read_slot(slot: int) -> RefCounted:
	if not _valid_slot(slot):
		return null
	var primary := _decode_file(_slot_path(slot), slot)
	if primary != null:
		return primary
	return _decode_file(_backup_path(slot), slot)


func delete_slot(slot: int) -> bool:
	if not _valid_slot(slot):
		return false
	for path: String in [
		_slot_path(slot),
		_slot_path(slot) + ".tmp",
		_backup_path(slot),
	]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	return read_slot(slot) == null


func _decode_file(path: String, slot: int) -> RefCounted:
	if not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var text := file.get_as_text()
	file.close()
	var codec: RefCounted = SAVE_CODEC.new()
	return codec.decode(text, slot)


func _ensure_root() -> bool:
	return DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(root_path)
	) == OK


func _slot_path(slot: int) -> String:
	return "%s/slot_%d.json" % [root_path, slot]


func _backup_path(slot: int) -> String:
	return "%s/slot_%d.backup.json" % [root_path, slot]


func _valid_slot(slot: int) -> bool:
	return slot >= 1 and slot <= 3
