class_name WorldRuntime
extends Node2D

signal current_room_changed(room_id: String)
signal room_loaded(room_id: String, room_runtime: Node)
signal room_unloaded(room_id: String)
signal transition_completed(from_room_id: String, to_room_id: String, spawn_id: String)

const ROOM_RUNTIME_SCRIPT: Script = preload("res://scripts/world/room_runtime.gd")
const WORLD_DATA_SCRIPT: Script = preload("res://scripts/world/world_data.gd")
const ROOM_TRANSITION: Script = preload("res://scripts/world/room_transition.gd")
const SAVE_SNAPSHOT_SCRIPT: Script = preload("res://scripts/save/save_snapshot.gd")

@export var world_data: Resource
@export var track_player_room := true

var _current_room_id := ""
var _loaded_rooms: Dictionary[String, Node] = {}
var _snapshot: RefCounted
var _player: Node2D
var _save_manager: Node
var _persistence_suspended := false
var _last_player_chunk := Vector2i.ZERO
var _has_last_player_chunk := false
var _last_safe_player_position := Vector2.ZERO


func _physics_process(_delta: float) -> void:
	if _player != null and not is_instance_valid(_player):
		_player = null
	if track_player_room and _player != null:
		update_player_room()


func setup_world(data: Resource) -> bool:
	if not _is_world_data(data) or data.start_room_id.is_empty() or not data.has_room(data.start_room_id):
		return false
	var start_chunk := _get_room_origin_chunk(data, data.start_room_id)
	if is_instance_valid(_player):
		start_chunk = data.get_chunk_at_world_position(to_local(_player.global_position))
	var staged_value: Variant = _stage_world(data, data.start_room_id, start_chunk, _get_save_manager())
	if staged_value == null:
		return false
	_snapshot = null
	_commit_world(data, data.start_room_id, staged_value as Dictionary)
	_record_player_tracking()
	return true


func setup_session(data: Resource, snapshot: RefCounted, player: Node2D = null) -> bool:
	if not _is_world_data(data) or not _is_save_snapshot(snapshot):
		return false
	var reset_respawn: bool = snapshot.world_id != data.world_id
	var initial_room_id: String = data.start_room_id
	var initial_spawn_id: String = data.start_spawn_id
	if snapshot.world_id == data.world_id:
		if data.has_room(snapshot.respawn_room_id) and not snapshot.respawn_spawn_id.is_empty():
			initial_room_id = snapshot.respawn_room_id
			initial_spawn_id = snapshot.respawn_spawn_id
		elif data.has_room(snapshot.current_room_id):
			initial_room_id = snapshot.current_room_id

	var staged_value: Variant = _stage_world(data, initial_room_id, _get_room_origin_chunk(data, initial_room_id), snapshot)
	if staged_value == null:
		return false
	var staged_rooms := staged_value as Dictionary
	var spawn := _get_spawn_point_from_rooms(staged_rooms, initial_room_id, initial_spawn_id)
	if not initial_spawn_id.is_empty() and spawn == null:
		_free_staged_rooms(staged_rooms)
		staged_value = _stage_world(
			data,
			data.start_room_id,
			_get_room_origin_chunk(data, data.start_room_id),
			snapshot
		)
		if staged_value == null:
			return false
		staged_rooms = staged_value as Dictionary
		initial_room_id = data.start_room_id
		initial_spawn_id = data.start_spawn_id
		spawn = _get_spawn_point_from_rooms(staged_rooms, initial_room_id, initial_spawn_id)
		if not initial_spawn_id.is_empty() and spawn == null:
			_free_staged_rooms(staged_rooms)
			return false
		reset_respawn = true
	if spawn != null and not _align_staged_world_to_spawn(
		data,
		initial_room_id,
		spawn,
		snapshot,
		staged_rooms
	):
		_free_staged_rooms(staged_rooms)
		return false

	_snapshot = snapshot
	_player = player
	_persistence_suspended = true
	_commit_world(data, initial_room_id, staged_rooms)
	if spawn != null:
		_respawn_player(spawn.global_position)
	_initialize_snapshot(initial_room_id, initial_spawn_id, spawn, reset_respawn)
	_persistence_suspended = false
	_record_player_tracking()
	_queue_snapshot_commit()
	return true


func bind_player(player: Node2D) -> void:
	_player = player


func synchronize_player_tracking() -> void:
	_record_player_tracking()


func bind_save_manager(save_manager: Node) -> void:
	_save_manager = save_manager


func update_player_room() -> bool:
	if not is_instance_valid(_player):
		_player = null
		return false
	if not _is_world_data(world_data):
		return false
	var local_position := to_local(_player.global_position)
	var player_chunk: Vector2i = world_data.get_chunk_at_world_position(local_position)
	if _has_last_player_chunk and player_chunk == _last_player_chunk:
		_last_safe_player_position = _player.global_position
		return true
	var room_id: String = world_data.get_room_id_at_world_position(local_position, _current_room_id)
	if room_id.is_empty():
		_restore_last_safe_player_position()
		return false
	var target_ids: Array[String] = world_data.get_resident_room_ids(player_chunk, room_id)
	var staged_value: Variant = _stage_missing_rooms(world_data, target_ids, _get_entity_state_source())
	if staged_value == null:
		_restore_last_safe_player_position()
		return false
	_commit_room_change(room_id, target_ids, staged_value as Dictionary)
	_last_player_chunk = player_chunk
	_has_last_player_chunk = true
	_last_safe_player_position = _player.global_position
	return true


func set_current_room(room_id: String) -> bool:
	if not _is_world_data(world_data) or not world_data.has_room(room_id):
		return false
	var player_chunk := _get_room_origin_chunk(world_data, room_id)
	if is_instance_valid(_player):
		player_chunk = world_data.get_chunk_at_world_position(to_local(_player.global_position))
	var target_ids := _get_target_room_ids_for(world_data, room_id, player_chunk)
	var staged_value: Variant = _stage_missing_rooms(world_data, target_ids, _get_entity_state_source())
	if staged_value == null:
		return false
	_commit_room_change(room_id, target_ids, staged_value as Dictionary)
	_record_player_tracking()
	return true


func refresh_loaded_rooms() -> bool:
	if not _is_world_data(world_data) or _current_room_id.is_empty():
		return false

	var target_ids := _get_target_room_ids_for(world_data, _current_room_id, _get_tracking_chunk())
	var staged_value: Variant = _stage_missing_rooms(world_data, target_ids, _get_entity_state_source())
	if staged_value == null:
		return false
	_register_staged_rooms(staged_value as Dictionary)
	_unload_rooms_outside(target_ids)
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


func clear_world() -> void:
	_unload_all_rooms()
	world_data = null
	_current_room_id = ""
	_snapshot = null
	_player = null
	_persistence_suspended = false
	_reset_player_tracking()


func request_transition(entrance: Node) -> bool:
	var source_room: Node = get_room_runtime(_current_room_id)
	if entrance == null or source_room == null or not source_room.is_ancestor_of(entrance):
		return false
	var transition: Dictionary = ROOM_TRANSITION.resolve(world_data, _current_room_id, entrance)
	if transition.is_empty():
		return false
	var target_room_id := String(transition.to_room_id)
	var target_spawn_id := String(transition.to_spawn_id)
	var target_ids := _get_target_room_ids_for(
		world_data,
		target_room_id,
		_get_room_origin_chunk(world_data, target_room_id)
	)
	var staged_value: Variant = _stage_missing_rooms(world_data, target_ids, _get_entity_state_source())
	if staged_value == null:
		return false
	var staged_rooms := staged_value as Dictionary
	var target_runtime: Node = _loaded_rooms.get(target_room_id, staged_rooms.get(target_room_id, null))
	var spawn: Node2D = null
	if target_runtime != null:
		spawn = target_runtime.call("get_spawn_point", target_spawn_id) as Node2D
	if spawn == null:
		_free_staged_rooms(staged_rooms)
		return false
	var spawn_chunk: Vector2i = world_data.get_chunk_at_world_position(to_local(spawn.global_position))
	target_ids = _get_target_room_ids_for(world_data, target_room_id, spawn_chunk)
	var additional_value: Variant = _stage_missing_rooms(
		world_data,
		target_ids,
		_get_entity_state_source(),
		staged_rooms
	)
	if additional_value == null:
		_free_staged_rooms(staged_rooms)
		return false
	var additional_rooms := additional_value as Dictionary
	for room_id: String in additional_rooms:
		staged_rooms[room_id] = additional_rooms[room_id]
	additional_rooms.clear()
	_trim_staged_rooms(staged_rooms, target_ids)
	_commit_room_change(target_room_id, target_ids, staged_rooms)
	_respawn_player(spawn.global_position)
	_record_player_tracking()
	transition_completed.emit(transition.from_room_id, transition.to_room_id, transition.to_spawn_id)
	return true


func _get_target_room_ids_for(data: Resource, room_id: String, player_chunk: Vector2i) -> Array[String]:
	return data.get_resident_room_ids(player_chunk, room_id)


func _stage_world(
	data: Resource,
	room_id: String,
	player_chunk: Vector2i,
	state_source: Object
) -> Variant:
	var staged: Dictionary[String, Node] = {}
	for target_id: String in _get_target_room_ids_for(data, room_id, player_chunk):
		var room_runtime := _create_room_runtime(data, target_id, state_source)
		if room_runtime == null:
			_free_staged_rooms(staged)
			return null
		staged[target_id] = room_runtime
	return staged


func _stage_missing_rooms(
	data: Resource,
	target_ids: Array[String],
	state_source: Object,
	already_staged: Dictionary = {}
) -> Variant:
	var staged: Dictionary[String, Node] = {}
	for room_id: String in target_ids:
		if _loaded_rooms.has(room_id) or already_staged.has(room_id):
			continue
		var room_runtime := _create_room_runtime(data, room_id, state_source)
		if room_runtime == null:
			_free_staged_rooms(staged)
			return null
		staged[room_id] = room_runtime
	return staged


func _align_staged_world_to_spawn(
	data: Resource,
	room_id: String,
	spawn: Node2D,
	state_source: Object,
	staged: Dictionary
) -> bool:
	var spawn_chunk: Vector2i = data.get_chunk_at_world_position(to_local(spawn.global_position))
	var target_ids: Array[String] = data.get_resident_room_ids(spawn_chunk, room_id)
	for target_id: String in target_ids:
		if staged.has(target_id):
			continue
		var room_runtime := _create_room_runtime(data, target_id, state_source)
		if room_runtime == null:
			return false
		staged[target_id] = room_runtime
	_trim_staged_rooms(staged, target_ids)
	return true


func _trim_staged_rooms(staged: Dictionary, target_ids: Array[String]) -> void:
	for room_id: String in staged.keys():
		if target_ids.has(room_id):
			continue
		var room_runtime: Node = staged[room_id]
		staged.erase(room_id)
		if is_instance_valid(room_runtime):
			room_runtime.free()


func _create_room_runtime(data: Resource, room_id: String, state_source: Object) -> Node2D:
	var room_data: Resource = data.get_room(room_id)
	if room_data == null:
		return null
	var room_runtime: Node2D = ROOM_RUNTIME_SCRIPT.new() as Node2D
	add_child(room_runtime)
	if not room_runtime.setup_room(room_data, data.world_id, state_source):
		room_runtime.free()
		return null
	return room_runtime


func _commit_world(data: Resource, room_id: String, staged_rooms: Dictionary) -> void:
	var changed := _current_room_id != room_id or world_data != data
	_unload_all_rooms()
	world_data = data
	_current_room_id = room_id
	_register_staged_rooms(staged_rooms)
	if changed:
		current_room_changed.emit(room_id)


func _commit_room_change(room_id: String, target_ids: Array[String], staged_rooms: Dictionary) -> void:
	_register_staged_rooms(staged_rooms)
	var changed := _current_room_id != room_id
	_current_room_id = room_id
	_unload_rooms_outside(target_ids)
	if changed:
		_persist_current_room()
		current_room_changed.emit(room_id)


func _register_staged_rooms(staged_rooms: Dictionary) -> void:
	var room_ids: Array[String] = []
	room_ids.assign(staged_rooms.keys())
	room_ids.sort()
	for room_id: String in room_ids:
		var room_runtime: Node = staged_rooms[room_id]
		room_runtime.connect("transition_requested", Callable(self, "request_transition"))
		_loaded_rooms[room_id] = room_runtime
		room_loaded.emit(room_id, room_runtime)
	staged_rooms.clear()


func _free_staged_rooms(staged_rooms: Dictionary) -> void:
	for room_runtime: Node in staged_rooms.values():
		if is_instance_valid(room_runtime):
			room_runtime.free()
	staged_rooms.clear()


func _unload_rooms_outside(target_ids: Array[String]) -> void:
	for room_id: String in _loaded_rooms.keys():
		if not target_ids.has(room_id):
			_unload_room(room_id)


func _unload_all_rooms() -> void:
	for room_id: String in _loaded_rooms.keys():
		_unload_room(room_id)


func _unload_room(room_id: String) -> void:
	if not _loaded_rooms.has(room_id):
		return
	var room_runtime: Node = _loaded_rooms[room_id]
	_loaded_rooms.erase(room_id)
	if room_runtime != null:
		room_runtime.free()
	room_unloaded.emit(room_id)


func _get_spawn_point(room_id: String, spawn_id: String) -> Node2D:
	if spawn_id.is_empty():
		return null
	var room_runtime: Node = get_room_runtime(room_id)
	if room_runtime == null or not room_runtime.has_method("get_spawn_point"):
		return null
	return room_runtime.call("get_spawn_point", spawn_id) as Node2D


func _get_spawn_point_from_rooms(rooms: Dictionary, room_id: String, spawn_id: String) -> Node2D:
	if spawn_id.is_empty() or not rooms.has(room_id):
		return null
	var room_runtime: Node = rooms[room_id]
	return room_runtime.call("get_spawn_point", spawn_id) as Node2D


func _respawn_player(position: Vector2) -> void:
	if not is_instance_valid(_player):
		_player = null
		return
	if _player.has_method("respawn_at"):
		_player.call("respawn_at", position)
	else:
		_player.global_position = position


func _get_room_origin_chunk(data: Resource, room_id: String) -> Vector2i:
	var room: Resource = data.get_room(room_id)
	return Vector2i.ZERO if room == null else room.room_origin_chunk


func _get_tracking_chunk() -> Vector2i:
	if _has_last_player_chunk:
		return _last_player_chunk
	return _get_room_origin_chunk(world_data, _current_room_id)


func _record_player_tracking() -> void:
	if not is_instance_valid(_player) or not _is_world_data(world_data):
		_reset_player_tracking()
		return
	_last_safe_player_position = _player.global_position
	_last_player_chunk = world_data.get_chunk_at_world_position(to_local(_player.global_position))
	_has_last_player_chunk = true


func _reset_player_tracking() -> void:
	_has_last_player_chunk = false
	_last_player_chunk = Vector2i.ZERO
	_last_safe_player_position = Vector2.ZERO


func _restore_last_safe_player_position() -> void:
	if _has_last_player_chunk and is_instance_valid(_player):
		_player.global_position = _last_safe_player_position


func _initialize_snapshot(
	room_id: String,
	spawn_id: String,
	spawn: Node2D,
	reset_respawn: bool
) -> void:
	if _snapshot == null:
		return
	_snapshot.world_id = world_data.world_id
	_snapshot.current_room_id = room_id
	if reset_respawn or _snapshot.respawn_room_id.is_empty():
		_snapshot.respawn_room_id = room_id
		_snapshot.respawn_spawn_id = spawn_id
		if spawn != null:
			_snapshot.respawn_position = spawn.global_position


func _persist_current_room() -> void:
	if _snapshot == null or not _is_world_data(world_data):
		return
	_snapshot.world_id = world_data.world_id
	_snapshot.current_room_id = _current_room_id
	_queue_snapshot_commit()


func _queue_snapshot_commit() -> void:
	if _persistence_suspended:
		return
	var manager := _get_save_manager()
	if manager != null and manager.has_method("queue_commit") and manager.get("current_snapshot") == _snapshot:
		manager.call("queue_commit")


func _get_save_manager() -> Node:
	if is_instance_valid(_save_manager):
		return _save_manager
	if is_inside_tree():
		return get_tree().root.get_node_or_null("SaveManager")
	return null


func _get_entity_state_source() -> Object:
	if _snapshot != null:
		return _snapshot
	return _get_save_manager()


static func _is_world_data(resource: Resource) -> bool:
	return resource != null and resource.get_script() == WORLD_DATA_SCRIPT


static func _is_save_snapshot(snapshot: RefCounted) -> bool:
	return snapshot != null and snapshot.get_script() == SAVE_SNAPSHOT_SCRIPT
