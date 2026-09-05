class_name WorldRuntime
extends Node2D

signal current_room_changed(room_id: String)
signal room_loaded(room_id: String, room_runtime: Node)
signal room_unloaded(room_id: String)
signal transition_completed(from_room_id: String, to_room_id: String, spawn_id: String)

const ROOM_RUNTIME_SCRIPT: Script = preload("res://scripts/world/room_runtime.gd")
const WORLD_DATA_SCRIPT: Script = preload("res://scripts/world/world_data.gd")
const ROOM_TRANSITION: Script = preload("res://scripts/world/room_transition.gd")

@export var world_data: Resource

var _current_room_id := ""
var _loaded_rooms: Dictionary[String, Node] = {}


func setup_world(data: Resource) -> bool:
	_current_room_id = ""
	_unload_all_rooms()
	world_data = null
	if not _is_world_data(data) or data.start_room_id.is_empty():
		return false
	world_data = data
	return set_current_room(world_data.start_room_id)


func set_current_room(room_id: String) -> bool:
	if not _is_world_data(world_data) or not world_data.has_room(room_id):
		return false
	if not _ensure_room_loaded(room_id):
		return false

	var changed := _current_room_id != room_id
	_current_room_id = room_id
	if not refresh_loaded_rooms():
		return false
	if changed:
		current_room_changed.emit(_current_room_id)
	return true


func refresh_loaded_rooms() -> bool:
	if not _is_world_data(world_data) or _current_room_id.is_empty():
		return false

	var target_ids := _get_target_room_ids()
	if not _ensure_room_loaded(_current_room_id):
		return false

	for room_id: String in target_ids:
		if _loaded_rooms.has(room_id):
			continue
		_load_room(room_id)

	for room_id: String in _loaded_rooms.keys():
		if not target_ids.has(room_id):
			var room_runtime: Node = _loaded_rooms[room_id]
			_loaded_rooms.erase(room_id)
			if room_runtime != null:
				room_runtime.free()
			room_unloaded.emit(room_id)

	return _loaded_rooms.has(_current_room_id)


func get_current_room_id() -> String:
	return _current_room_id


func get_loaded_room_ids() -> Array[String]:
	var result: Array[String] = []
	result.assign(_loaded_rooms.keys())
	result.sort()
	return result


func get_room_runtime(room_id: String) -> Node:
	return _loaded_rooms.get(room_id, null)


func request_transition(entrance: Node) -> bool:
	var transition: Dictionary = ROOM_TRANSITION.resolve(world_data, _current_room_id, entrance)
	if transition.is_empty() or not set_current_room(transition.to_room_id):
		return false
	transition_completed.emit(transition.from_room_id, transition.to_room_id, transition.to_spawn_id)
	return true


func _get_target_room_ids() -> Array[String]:
	var unique: Dictionary[String, bool] = {_current_room_id: true}
	for adjacent_id: String in world_data.get_adjacent_room_ids(_current_room_id):
		if world_data.has_room(adjacent_id):
			unique[adjacent_id] = true

	var result: Array[String] = []
	result.assign(unique.keys())
	result.sort()
	return result


func _load_room(room_id: String) -> bool:
	var room_data: Resource = world_data.get_room(room_id)
	if room_data == null:
		return false

	var room_runtime: Node2D = ROOM_RUNTIME_SCRIPT.new() as Node2D
	if not room_runtime.setup_room(room_data):
		room_runtime.free()
		return false

	add_child(room_runtime)
	_loaded_rooms[room_id] = room_runtime
	room_loaded.emit(room_id, room_runtime)
	return true


func _ensure_room_loaded(room_id: String) -> bool:
	if _loaded_rooms.has(room_id):
		return true
	return _load_room(room_id)


func _unload_all_rooms() -> void:
	for room_id: String in _loaded_rooms.keys():
		var room_runtime: Node = _loaded_rooms[room_id]
		if room_runtime != null:
			room_runtime.free()
		room_unloaded.emit(room_id)
	_loaded_rooms.clear()


static func _is_world_data(resource: Resource) -> bool:
	return resource != null and resource.get_script() == WORLD_DATA_SCRIPT
