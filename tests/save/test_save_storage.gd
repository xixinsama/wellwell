extends Node

const SAVE_SNAPSHOT: Script = preload("res://scripts/save/save_snapshot.gd")
const SAVE_STORAGE: Script = preload("res://scripts/save/save_storage.gd")

const TEST_ROOT := "user://wellwell_storage_test"


func run() -> Array[String]:
	var failures: Array[String] = []
	_clear()
	_assert_write_and_read_slot(failures)
	_clear()
	_assert_backup_is_used_when_primary_is_invalid(failures)
	_clear()
	return failures


func _assert_write_and_read_slot(failures: Array[String]) -> void:
	var storage: RefCounted = SAVE_STORAGE.new(TEST_ROOT)
	var snapshot: RefCounted = SAVE_SNAPSHOT.new()
	snapshot.slot = 1
	snapshot.respawn_position = Vector2(16, 24)
	snapshot.add_explored_cell("level_01:2,3")

	if not storage.write_slot(snapshot):
		failures.append("write_slot returned false")
		return
	var loaded: RefCounted = storage.read_slot(1)
	if loaded == null:
		failures.append("read_slot returned null")
		return
	if loaded.respawn_position != Vector2(16, 24):
		failures.append("loaded respawn position was wrong")
	if not loaded.has_explored_cell("level_01:2,3"):
		failures.append("loaded explored cell was missing")


func _assert_backup_is_used_when_primary_is_invalid(failures: Array[String]) -> void:
	var storage: RefCounted = SAVE_STORAGE.new(TEST_ROOT)
	var snapshot: RefCounted = SAVE_SNAPSHOT.new()
	snapshot.slot = 1
	snapshot.add_explored_cell("level_01:backup")
	if not storage.write_slot(snapshot):
		failures.append("initial write failed")
		return

	var primary_path := "%s/slot_1.json" % TEST_ROOT
	var backup_path := "%s/slot_1.backup.json" % TEST_ROOT
	DirAccess.rename_absolute(
		ProjectSettings.globalize_path(primary_path),
		ProjectSettings.globalize_path(backup_path)
	)
	var file := FileAccess.open(primary_path, FileAccess.WRITE)
	file.store_string("{broken")
	file.close()

	var loaded: RefCounted = storage.read_slot(1)
	if loaded == null or not loaded.has_explored_cell("level_01:backup"):
		failures.append("backup snapshot was not loaded")


func _clear() -> void:
	var storage: RefCounted = SAVE_STORAGE.new(TEST_ROOT)
	storage.delete_slot(1)
	var root := ProjectSettings.globalize_path(TEST_ROOT)
	if DirAccess.dir_exists_absolute(root):
		DirAccess.remove_absolute(root)
