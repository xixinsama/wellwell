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
	start_or_continue(1)


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
		start_or_continue(1)
	if current_snapshot == null:
		return false
	var changed: bool = current_snapshot.add_explored_cell(cell_id)
	if changed:
		queue_commit()
	return changed


func has_explored_cell(cell_id: String) -> bool:
	if current_snapshot == null:
		start_or_continue(1)
	return current_snapshot != null and current_snapshot.has_explored_cell(cell_id)


func get_explored_cells() -> Array[String]:
	if current_snapshot == null:
		start_or_continue(1)
	if current_snapshot == null:
		return []
	return current_snapshot.get_explored_cells()


func queue_commit(delay_seconds: float = 0.35) -> void:
	if _commit_timer == null:
		commit()
		return
	_commit_timer.start(maxf(delay_seconds, 0.01))


func _on_commit_timer_timeout() -> void:
	commit()
