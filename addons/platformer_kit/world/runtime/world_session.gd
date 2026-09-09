class_name WorldSession
extends Node2D

const WORLD_VALIDATION := preload("res://addons/platformer_kit/world/data/world_validation.gd")
const SAVE_SNAPSHOT := preload("res://addons/platformer_kit/save/save_snapshot.gd")

signal world_ready()
signal world_start_failed(errors: Array[String])

@export var world_data: WorldData
@export var terrain_runtime_path := NodePath("TerrainRoot")
@export var world_runtime_path := NodePath("WorldRuntime")
@export var player_path := NodePath("Player")
@export var camera_path := NodePath("PixelCamera2D")
@export var debug_hud_path: NodePath

var _active_world: WorldData
var _active_snapshot: RefCounted
var _persistence_source: Object
var _settings_source: Object
var _last_start_errors: Array[String] = []
var _room_extensions: Array[Node] = []
var _save_commit_source: Object


func _enter_tree() -> void:
	for extension: Node in _room_extensions:
		if extension != null and extension.has_method("clear_room"):
			extension.call("clear_room")


func _exit_tree() -> void:
	_unbind_save_flush()


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
	var hud := get_node_or_null(debug_hud_path)
	if terrain_runtime == null or runtime == null or player == null or camera == null:
		return _report_failure(["WorldSession is missing required persistent nodes"])
	var previous := _capture_active_state(runtime, player)
	var target_snapshot_state: Dictionary = snapshot.to_dictionary()
	if runtime.has_method("bind_persistence_source"):
		runtime.call("bind_persistence_source", _persistence_source)
	if not bool(terrain_runtime.call("setup_world", target_world)):
		_rollback_start(previous, terrain_runtime, runtime, player)
		_restore_snapshot(snapshot, target_snapshot_state)
		return _report_failure(["persistent terrain setup failed"])
	if not bool(runtime.call("setup_session", target_world, snapshot, player)):
		_rollback_start(previous, terrain_runtime, runtime, player)
		_restore_snapshot(snapshot, target_snapshot_state)
		return _report_failure(["streamed world runtime setup failed"])
	_bind_save_flush(runtime)
	if camera.has_method("bind_target"):
		camera.call("bind_target", player)
	_bind_extension_context(player)
	if hud != null and hud.has_method("bind_player"):
		hud.call("bind_player", player)
	var room_id := String(runtime.call("get_current_room_id"))
	if not _bind_room_extensions(target_world, room_id, terrain_runtime):
		_rollback_start(previous, terrain_runtime, runtime, player)
		_restore_snapshot(snapshot, target_snapshot_state)
		return _report_failure(["active room extension binding failed"])
	_configure_camera_for_room(camera, target_world, room_id)
	var callback := Callable(self, "_on_current_room_changed").bind(terrain_runtime, camera)
	if runtime.has_signal("current_room_changed") and not runtime.is_connected("current_room_changed", callback):
		runtime.connect("current_room_changed", callback)
	_active_world = target_world
	_active_snapshot = snapshot
	world_data = target_world
	world_ready.emit()
	return true


func start_selected_snapshot(snapshot: RefCounted) -> bool:
	return start(world_data, snapshot)


func bind_persistence_source(source: Object) -> void:
	if source != _persistence_source:
		_unbind_save_flush()
	_persistence_source = source
	var runtime := get_node_or_null(world_runtime_path)
	if runtime != null and runtime.has_method("bind_persistence_source"):
		runtime.call("bind_persistence_source", source)


func bind_settings_source(source: Object) -> void:
	_settings_source = source
	for extension: Node in _room_extensions:
		if extension != null and extension.has_method("bind_settings_source"):
			extension.call("bind_settings_source", source)


func register_room_extension(extension: Node) -> bool:
	if extension == null or _room_extensions.has(extension):
		return false
	_room_extensions.append(extension)
	var player := get_node_or_null(player_path) as Node2D
	if player != null and extension.has_method("bind_player"):
		extension.call("bind_player", player)
	if extension.has_method("bind_settings_source"):
		extension.call("bind_settings_source", _settings_source)
	return true


func unregister_room_extension(extension: Node) -> bool:
	var index := _room_extensions.find(extension)
	if index < 0:
		return false
	_room_extensions.remove_at(index)
	return true


func get_last_start_errors() -> Array[String]:
	return _last_start_errors.duplicate()


func stop() -> void:
	_unbind_save_flush()
	var terrain_runtime := get_node_or_null(terrain_runtime_path)
	var runtime := get_node_or_null(world_runtime_path)
	var camera := get_node_or_null(camera_path)
	if terrain_runtime != null and terrain_runtime.has_method("clear_world"):
		terrain_runtime.call("clear_world")
	if runtime != null and runtime.has_method("clear_world"):
		runtime.call("clear_world")
	_clear_room_extensions()
	if camera != null and camera.has_method("clear_room_bounds"):
		camera.call("clear_room_bounds")
	_active_world = null
	_active_snapshot = null


func _on_current_room_changed(room_id: String, terrain_runtime: Node, camera: Node) -> void:
	if _active_world != null:
		if _bind_room_extensions(_active_world, room_id, terrain_runtime):
			_configure_camera_for_room(camera, _active_world, room_id)


func _configure_camera_for_room(camera: Node, world: WorldData, room_id: String) -> void:
	if camera == null or world == null:
		return
	if camera.has_method("set_room_bounds"):
		camera.call("set_room_bounds", Rect2(world.get_room_pixel_rect(room_id)))


func _bind_room_extensions(world: WorldData, room_id: String, terrain_runtime: Node) -> bool:
	var room: Resource = world.get_room(room_id)
	var terrain: Node = terrain_runtime.call("get_room_terrain", room_id)
	if room == null or terrain == null:
		return false
	for extension: Node in _room_extensions:
		if extension == null:
			continue
		var accepted := true
		if extension.has_method("bind_room_with_origin"):
			accepted = bool(extension.call("bind_room_with_origin", room, terrain, world.get_room_origin_chunk(room_id)))
		elif extension.has_method("bind_room"):
			accepted = bool(extension.call("bind_room", room, terrain))
		if not accepted:
			return false
	return true


func _bind_extension_context(player: Node2D) -> void:
	for extension: Node in _room_extensions:
		if extension == null:
			continue
		if extension.has_method("bind_player"):
			extension.call("bind_player", player)
		if extension.has_method("bind_settings_source"):
			extension.call("bind_settings_source", _settings_source)


func _clear_room_extensions() -> void:
	for extension: Node in _room_extensions:
		if extension != null and extension.has_method("clear_room"):
			extension.call("clear_room")


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


func _rollback_start(previous: Dictionary, terrain_runtime: Node, runtime: Node, player: Node2D) -> void:
	var previous_world := previous.get("world") as WorldData
	var previous_snapshot := previous.get("snapshot") as RefCounted
	if previous_world == null or previous_snapshot == null:
		if terrain_runtime.has_method("clear_world"):
			terrain_runtime.call("clear_world")
		if runtime.has_method("clear_world"):
			runtime.call("clear_world")
		_clear_room_extensions()
		return
	terrain_runtime.call("setup_world", previous_world)
	runtime.call("setup_session", previous_world, previous_snapshot, player)
	var previous_room_id := String(previous.get("room_id", ""))
	if runtime.has_method("set_current_room") and String(runtime.call("get_current_room_id")) != previous_room_id:
		runtime.call("set_current_room", previous_room_id)
	player.global_position = previous.get("player_position", player.global_position)
	if runtime.has_method("synchronize_player_tracking"):
		runtime.call("synchronize_player_tracking")
	_bind_room_extensions(previous_world, String(runtime.call("get_current_room_id")), terrain_runtime)


func _restore_snapshot(snapshot: RefCounted, state: Dictionary) -> void:
	if snapshot != null and snapshot.has_method("load_from_dictionary"):
		snapshot.call("load_from_dictionary", state)


func _report_failure(errors: Array[String]) -> bool:
	_last_start_errors = errors.duplicate()
	world_start_failed.emit(_last_start_errors)
	return false


func _bind_save_flush(runtime: Node) -> void:
	if runtime == null or not runtime.has_method("persist_loaded_entity_states"):
		return
	var manager := _persistence_source
	if manager == null or not manager.has_signal("snapshot_committing"):
		return
	_unbind_save_flush()
	var callback := Callable(self, "_on_snapshot_committing")
	if not manager.is_connected("snapshot_committing", callback):
		manager.connect("snapshot_committing", callback)
	_save_commit_source = manager


func _unbind_save_flush() -> void:
	if not is_instance_valid(_save_commit_source):
		_save_commit_source = null
		return
	var callback := Callable(self, "_on_snapshot_committing")
	if _save_commit_source.has_signal("snapshot_committing") and _save_commit_source.is_connected("snapshot_committing", callback):
		_save_commit_source.disconnect("snapshot_committing", callback)
	_save_commit_source = null


func _on_snapshot_committing(snapshot: RefCounted) -> void:
	if snapshot == null or snapshot != _active_snapshot:
		return
	var runtime := get_node_or_null(world_runtime_path)
	if runtime != null and runtime.has_method("persist_loaded_entity_states"):
		runtime.call("persist_loaded_entity_states")
