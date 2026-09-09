class_name MetroidvaniaPersistenceBridge
extends Node

const SAVE_ADAPTER := preload("res://addons/metroidvania_kit/world_state/metroidvania_save_adapter.gd")
const MODULE_ID: StringName = &"metroidvania_kit"

var _save_manager: Node
var _progression: RefCounted
var _discovery: RefCounted
var _markers: RefCounted
var _world_state: RefCounted
var _fast_travel: RefCounted
var _fog: Node
var _adapter: RefCounted = SAVE_ADAPTER.new()
var _explored_cells: Dictionary[String, bool] = {}
var _explored_chunks: Dictionary[String, bool] = {}


func _exit_tree() -> void:
	_disconnect_save_manager()


func configure(
	progression: RefCounted,
	discovery: RefCounted,
	markers: RefCounted,
	world_state: RefCounted,
	fast_travel: RefCounted,
	fog: Node = null
) -> void:
	_progression = progression
	_discovery = discovery
	_markers = markers
	_world_state = world_state
	_fast_travel = fast_travel
	bind_fog(fog)


func bind_save_manager(save_manager: Node) -> bool:
	_disconnect_save_manager()
	if save_manager == null or not save_manager.has_signal("snapshot_committing") or not save_manager.has_signal("slot_selected"):
		return false
	_save_manager = save_manager
	_save_manager.connect("snapshot_committing", Callable(self, "_on_snapshot_committing"))
	_save_manager.connect("slot_selected", Callable(self, "_on_slot_selected"))
	var snapshot := _save_manager.get("current_snapshot") as RefCounted
	if snapshot != null:
		_restore(snapshot)
	return true


func bind_fog(fog: Node) -> void:
	_fog = fog
	if _fog != null and _fog.has_method("bind_persistence_source"):
		_fog.call("bind_persistence_source", self)
	_sync_fog()


func mark_cell_explored(cell_id: String) -> bool:
	if cell_id.is_empty() or _explored_cells.has(cell_id):
		return false
	_explored_cells[cell_id] = true
	_queue_commit()
	return true


func mark_chunk_explored(chunk_id: String) -> bool:
	if chunk_id.is_empty() or _explored_chunks.has(chunk_id):
		return false
	_explored_chunks[chunk_id] = true
	_queue_commit()
	return true


func get_explored_cells() -> Array[String]:
	var result: Array[String] = []
	result.assign(_explored_cells.keys())
	result.sort()
	return result


func get_explored_chunks() -> Array[String]:
	var result: Array[String] = []
	result.assign(_explored_chunks.keys())
	result.sort()
	return result


func _on_snapshot_committing(snapshot: RefCounted) -> void:
	_adapter.call("capture", snapshot, _progression, _discovery, _markers, _world_state, _fast_travel)
	var state: Dictionary = snapshot.call("get_module_state", MODULE_ID)
	state["fog"] = {
		"cells": get_explored_cells(),
		"chunks": get_explored_chunks(),
	}
	snapshot.call("set_module_state", MODULE_ID, state)


func _on_slot_selected(_slot: int, snapshot: RefCounted) -> void:
	_restore(snapshot)


func _restore(snapshot: RefCounted) -> bool:
	var state: Dictionary = snapshot.call("get_module_state", MODULE_ID)
	if state.is_empty():
		if not _adapter.call("reset", _progression, _discovery, _markers, _world_state, _fast_travel):
			return false
		_explored_cells.clear()
		_explored_chunks.clear()
		_sync_fog()
		return true
	var parsed_fog: Variant = _parse_fog_state(state.get("fog", {}))
	if parsed_fog == null:
		return false
	if not _adapter.call("restore", snapshot, _progression, _discovery, _markers, _world_state, _fast_travel):
		return false
	_explored_cells = parsed_fog["cells"]
	_explored_chunks = parsed_fog["chunks"]
	_sync_fog()
	return true


func _parse_fog_state(fog_state: Variant) -> Variant:
	if not fog_state is Dictionary:
		return null
	var cells: Variant = fog_state.get("cells", [])
	var chunks: Variant = fog_state.get("chunks", [])
	if not cells is Array or not chunks is Array:
		return null
	var parsed_cells: Dictionary[String, bool] = {}
	var parsed_chunks: Dictionary[String, bool] = {}
	for value: Variant in cells:
		if not value is String or String(value).is_empty():
			return null
		parsed_cells[String(value)] = true
	for value: Variant in chunks:
		if not value is String or String(value).is_empty():
			return null
		parsed_chunks[String(value)] = true
	return {"cells": parsed_cells, "chunks": parsed_chunks}


func _sync_fog() -> void:
	if _fog != null and _fog.has_method("replace_explored_cells"):
		_fog.call("replace_explored_cells", get_explored_cells())


func _queue_commit() -> void:
	if _save_manager != null and _save_manager.has_method("queue_commit"):
		_save_manager.call("queue_commit")


func _disconnect_save_manager() -> void:
	if _save_manager == null:
		return
	for signal_name: StringName in [&"snapshot_committing", &"slot_selected"]:
		var method_name := "_on_%s" % signal_name
		var callback := Callable(self, method_name)
		if _save_manager.is_connected(signal_name, callback):
			_save_manager.disconnect(signal_name, callback)
	_save_manager = null
