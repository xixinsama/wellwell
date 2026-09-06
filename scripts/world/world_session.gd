class_name WorldSession
extends Node2D

const WORLD_VALIDATION := preload("res://scripts/world/world_validation.gd")
const SAVE_SNAPSHOT := preload("res://scripts/save/save_snapshot.gd")

signal world_ready()
signal world_start_failed(errors: Array[String])

@export var world_data: WorldData
@export var terrain_runtime_path := NodePath("TerrainRoot")
@export var world_runtime_path := NodePath("WorldRuntime")
@export var player_path := NodePath("Player")
@export var camera_path := NodePath("PixelCamera2D")
@export var fog_path := NodePath("FogOfWar")
@export var debug_hud_path := NodePath("../../../HUD/DebugHud")

var _active_world: WorldData
var _active_snapshot: RefCounted
var _persistence_snapshot: RefCounted
var _last_start_errors: Array[String] = []


func _enter_tree() -> void:
	var fog := get_node_or_null(fog_path)
	var player := get_node_or_null(player_path) as Node2D
	if fog != null:
		if fog.has_method("bind_player"):
			fog.call("bind_player", player)
		if fog.has_method("clear_room"):
			fog.call("clear_room")


func start(world: WorldData = null, snapshot: RefCounted = null) -> bool:
	_last_start_errors.clear()
	var target_world := world if world != null else world_data
	var errors := _preflight_world(target_world)
	if snapshot == null or snapshot.get_script() != SAVE_SNAPSHOT:
		errors.append("save snapshot is invalid")
	if not errors.is_empty():
		return _report_failure(errors)
	var terrain_runtime := get_node_or_null(terrain_runtime_path)
	var runtime := get_node_or_null(world_runtime_path)
	var player := get_node_or_null(player_path) as Node2D
	var camera := get_node_or_null(camera_path)
	var fog := get_node_or_null(fog_path)
	var hud := get_node_or_null(debug_hud_path)
	if terrain_runtime == null or runtime == null or player == null or camera == null or fog == null or hud == null:
		return _report_failure(["WorldSession is missing required persistent nodes"])
	var previous := _capture_active_state(runtime, player)
	var target_snapshot_state: Dictionary = snapshot.to_dictionary()
	_persistence_snapshot = snapshot
	if not bool(terrain_runtime.call("setup_world", target_world)):
		_rollback_start(previous, terrain_runtime, runtime, player, fog)
		_restore_snapshot(snapshot, target_snapshot_state)
		return _report_failure(["persistent terrain setup failed"])
	if not bool(runtime.call("setup_session", target_world, snapshot, player)):
		_rollback_start(previous, terrain_runtime, runtime, player, fog)
		_restore_snapshot(snapshot, target_snapshot_state)
		return _report_failure(["streamed world runtime setup failed"])
	if camera.has_method("bind_target"):
		camera.call("bind_target", player)
	if fog.has_method("bind_player"):
		fog.call("bind_player", player)
	if fog.has_method("bind_persistence_source"):
		fog.call("bind_persistence_source", self)
	if hud.has_method("bind_player"):
		hud.call("bind_player", player)
	var room_id := String(runtime.call("get_current_room_id"))
	if not _bind_fog_room(target_world, room_id, terrain_runtime, fog):
		_rollback_start(previous, terrain_runtime, runtime, player, fog)
		_restore_snapshot(snapshot, target_snapshot_state)
		return _report_failure(["active room fog binding failed"])
	var callback := Callable(self, "_on_current_room_changed").bind(terrain_runtime, fog)
	if runtime.has_signal("current_room_changed") and not runtime.is_connected("current_room_changed", callback):
		runtime.connect("current_room_changed", callback)
	_active_world = target_world
	_active_snapshot = snapshot
	world_data = target_world
	world_ready.emit()
	return true


func start_selected_snapshot(snapshot: RefCounted) -> bool:
	return start(world_data, snapshot)


func get_last_start_errors() -> Array[String]:
	return _last_start_errors.duplicate()


func stop() -> void:
	var terrain_runtime := get_node_or_null(terrain_runtime_path)
	var runtime := get_node_or_null(world_runtime_path)
	var fog := get_node_or_null(fog_path)
	if terrain_runtime != null and terrain_runtime.has_method("clear_world"):
		terrain_runtime.call("clear_world")
	if runtime != null and runtime.has_method("clear_world"):
		runtime.call("clear_world")
	if fog != null and fog.has_method("clear_room"):
		fog.call("clear_room")
	if fog != null and fog.has_method("clear_persistence_source"):
		fog.call("clear_persistence_source")
	_active_world = null
	_active_snapshot = null
	_persistence_snapshot = null


func mark_cell_explored(cell_id: String) -> bool:
	if _persistence_snapshot == null:
		return false
	var changed: bool = _persistence_snapshot.add_explored_cell(cell_id)
	if changed:
		_queue_snapshot_commit()
	return changed


func mark_chunk_explored(chunk_id: String) -> bool:
	if _persistence_snapshot == null:
		return false
	var changed: bool = _persistence_snapshot.add_explored_chunk(chunk_id)
	if changed:
		_queue_snapshot_commit()
	return changed


func get_explored_cells() -> Array[String]:
	return [] if _persistence_snapshot == null else _persistence_snapshot.get_explored_cells()


func get_explored_chunks() -> Array[String]:
	return [] if _persistence_snapshot == null else _persistence_snapshot.get_explored_chunks()


func _on_current_room_changed(room_id: String, terrain_runtime: Node, fog: Node) -> void:
	if _active_world != null:
		_bind_fog_room(_active_world, room_id, terrain_runtime, fog)


func _bind_fog_room(world: WorldData, room_id: String, terrain_runtime: Node, fog: Node) -> bool:
	var room: Resource = world.get_room(room_id)
	var terrain: Node = terrain_runtime.call("get_room_terrain", room_id)
	return room != null and terrain != null and bool(fog.call("bind_room", room, terrain))


func _preflight_world(world: WorldData) -> Array[String]:
	var report: Dictionary = WORLD_VALIDATION.validate_world_report(world)
	var errors: Array[String] = []
	errors.assign(report.get("errors", []))
	if world == null:
		return errors
	for room: Resource in world.rooms:
		if room == null:
			continue
		for path: String in [room.scene_path, room.terrain_scene_path]:
			if not path.is_empty() and not ResourceLoader.exists(path, "PackedScene"):
				errors.append("room artifact is missing: %s" % path)
	errors.sort()
	return errors


func _capture_active_state(runtime: Node, player: Node2D) -> Dictionary:
	return {
		"world": _active_world,
		"snapshot": _active_snapshot,
		"room_id": String(runtime.call("get_current_room_id")),
		"player_position": player.global_position,
	}


func _rollback_start(previous: Dictionary, terrain_runtime: Node, runtime: Node, player: Node2D, fog: Node) -> void:
	var previous_world := previous.get("world") as WorldData
	var previous_snapshot := previous.get("snapshot") as RefCounted
	_persistence_snapshot = previous_snapshot
	if previous_world == null or previous_snapshot == null:
		if terrain_runtime.has_method("clear_world"):
			terrain_runtime.call("clear_world")
		if runtime.has_method("clear_world"):
			runtime.call("clear_world")
		if fog.has_method("clear_room"):
			fog.call("clear_room")
		if fog.has_method("clear_persistence_source"):
			fog.call("clear_persistence_source")
		return
	terrain_runtime.call("setup_world", previous_world)
	runtime.call("setup_session", previous_world, previous_snapshot, player)
	var previous_room_id := String(previous.get("room_id", ""))
	if runtime.has_method("set_current_room") and String(runtime.call("get_current_room_id")) != previous_room_id:
		runtime.call("set_current_room", previous_room_id)
	player.global_position = previous.get("player_position", player.global_position)
	if runtime.has_method("synchronize_player_tracking"):
		runtime.call("synchronize_player_tracking")
	if fog.has_method("bind_persistence_source"):
		fog.call("bind_persistence_source", self)
	_bind_fog_room(previous_world, String(runtime.call("get_current_room_id")), terrain_runtime, fog)


func _restore_snapshot(snapshot: RefCounted, state: Dictionary) -> void:
	if snapshot != null and snapshot.has_method("load_from_dictionary"):
		snapshot.call("load_from_dictionary", state)


func _report_failure(errors: Array[String]) -> bool:
	_last_start_errors = errors.duplicate()
	world_start_failed.emit(_last_start_errors)
	return false


func _queue_snapshot_commit() -> void:
	if not is_inside_tree() or _persistence_snapshot == null:
		return
	var manager := get_tree().root.get_node_or_null("SaveManager")
	if manager != null and manager.has_method("queue_commit") and manager.get("current_snapshot") == _persistence_snapshot:
		manager.call("queue_commit")
