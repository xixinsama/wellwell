class_name WellwellSaveManager
extends Node

signal slot_committed(slot: int)
signal slot_selected(slot: int, snapshot: RefCounted)

const SAVE_SNAPSHOT: Script = preload("res://scripts/save/save_snapshot.gd")
const SAVE_STORAGE: Script = preload("res://scripts/save/save_storage.gd")

var selected_slot := 0
var current_snapshot: RefCounted
var last_committed_snapshot: RefCounted
var _storage: RefCounted = SAVE_STORAGE.new()
var _commit_timer: Timer


func _ready() -> void:
	_commit_timer = Timer.new()
	_commit_timer.one_shot = true
	_commit_timer.timeout.connect(_on_commit_timer_timeout)
	add_child(_commit_timer)


func setup_storage(storage: RefCounted) -> void:
	_storage = storage


func start_or_continue(slot: int = 1) -> RefCounted:
	if slot < 1 or slot > 3:
		return null
	selected_slot = slot
	current_snapshot = _storage.read_slot(slot)
	if current_snapshot == null:
		current_snapshot = SAVE_SNAPSHOT.new()
		current_snapshot.slot = slot
		commit(current_snapshot)
	slot_selected.emit(slot, current_snapshot)
	return current_snapshot


func get_slot_summary(slot: int) -> Dictionary:
	var snapshot: RefCounted = _storage.read_slot(slot)
	if snapshot == null:
		return {"slot": slot, "occupied": false}
	return {
		"slot": slot,
		"occupied": true,
		"world_id": snapshot.world_id,
		"room_id": snapshot.current_room_id,
		"saved_unix_time": snapshot.saved_unix_time,
	}


func copy_slot(source_slot: int, target_slot: int) -> bool:
	if source_slot < 1 or source_slot > 3 or target_slot < 1 or target_slot > 3:
		return false
	var source: RefCounted = _storage.read_slot(source_slot)
	if source == null:
		return false
	var copied: RefCounted = SAVE_SNAPSHOT.new()
	copied.load_from_dictionary(source.to_dictionary())
	copied.slot = target_slot
	return _storage.write_slot(copied)


func delete_slot(slot: int) -> bool:
	var deleted: bool = _storage.delete_slot(slot)
	if deleted and selected_slot == slot:
		selected_slot = 0
		current_snapshot = null
		last_committed_snapshot = null
	return deleted


func quick_save() -> bool:
	return commit()


func quick_load() -> RefCounted:
	if selected_slot < 1:
		return null
	current_snapshot = _storage.read_slot(selected_slot)
	if current_snapshot != null:
		slot_selected.emit(selected_slot, current_snapshot)
	return current_snapshot


func commit(snapshot: RefCounted = null) -> bool:
	var target: RefCounted = snapshot if snapshot != null else current_snapshot
	if target == null or target.slot < 1 or target.slot > 3:
		return false
	if not _storage.write_slot(target):
		return false
	selected_slot = target.slot
	current_snapshot = target
	last_committed_snapshot = target
	slot_committed.emit(target.slot)
	return true


func mark_cell_explored(cell_id: String) -> bool:
	if current_snapshot == null:
		return false
	var changed: bool = current_snapshot.add_explored_cell(cell_id)
	if changed:
		queue_commit()
	return changed


func has_explored_cell(cell_id: String) -> bool:
	return current_snapshot != null and current_snapshot.has_explored_cell(cell_id)


func get_explored_cells() -> Array[String]:
	if current_snapshot == null:
		return []
	return current_snapshot.get_explored_cells()


func mark_chunk_explored(chunk_id: String) -> bool:
	if current_snapshot == null:
		return false
	var changed: bool = current_snapshot.add_explored_chunk(chunk_id)
	if changed:
		queue_commit()
	return changed


func is_chunk_explored(chunk_id: String) -> bool:
	return current_snapshot != null and current_snapshot.has_explored_chunk(chunk_id)


func set_entity_state(entity_key: String, state: Dictionary) -> void:
	if current_snapshot == null:
		return
	current_snapshot.set_entity_state(entity_key, state)
	queue_commit()


func get_entity_state(entity_key: String) -> Dictionary:
	return {} if current_snapshot == null else current_snapshot.get_entity_state(entity_key)


func set_respawn(room_id: String, spawn_id: String, position: Vector2 = Vector2.ZERO) -> void:
	if current_snapshot == null:
		return
	current_snapshot.respawn_room_id = room_id
	current_snapshot.respawn_spawn_id = spawn_id
	current_snapshot.respawn_position = position
	queue_commit()


func queue_commit(delay_seconds: float = 0.35) -> void:
	if _commit_timer == null:
		commit()
		return
	_commit_timer.start(maxf(delay_seconds, 0.01))


func _on_commit_timer_timeout() -> void:
	commit()
