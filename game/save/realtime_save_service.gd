class_name RealtimeSaveService
extends Node

## Captures the player's live transform into the active save snapshot while the
## Realtime Save setting is on. The service is scene-scoped: it lives under
## WorldRoot, so menu-only sessions never touch a save slot.

@export var player_path := NodePath("../Player")
@export var session_path := NodePath("..")
@export var interval_seconds := 2.0
@export var save_manager_path := NodePath("/root/SaveManager")
@export var settings_path := NodePath("/root/GlobalSettings")

var _player: Node
var _session: Node
var _save_manager: Node
var _settings: Node
var _enabled := false
var _active := false
var _elapsed := 0.0
var _last_position := Vector2.INF
var _last_velocity := Vector2.INF
var _close_flushed := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_resolve_sources()
	_connect_sources()
	_refresh_enabled()


func bind_sources(player: Node, save_manager: Node, settings: Node, session: Node = null) -> void:
	_player = player
	_save_manager = save_manager
	_settings = settings
	if session != null:
		_session = session
	_connect_sources()
	_refresh_enabled()


func set_active(value: bool) -> void:
	_active = value
	_elapsed = 0.0
	if _active and _enabled:
		capture_now()


func is_enabled() -> bool:
	return _enabled


func capture_now(immediate := false) -> bool:
	if not _enabled or not _active:
		return false
	if not is_instance_valid(_player) or not is_instance_valid(_save_manager):
		return false
	if _save_manager.get("current_snapshot") == null:
		return false
	var session_snapshot := _session_snapshot()
	if session_snapshot != null and _save_manager.get("current_snapshot") != session_snapshot:
		return false
	var current_position: Vector2 = _player.global_position
	var current_velocity := Vector2.ZERO
	if "velocity" in _player:
		current_velocity = Vector2(_player.get("velocity"))
	if current_position == _last_position and current_velocity == _last_velocity:
		return false
	if not _save_manager.has_method("set_resume_state"):
		return false
	var saved := bool(_save_manager.call("set_resume_state", current_position, current_velocity, immediate))
	if saved:
		_last_position = current_position
		_last_velocity = current_velocity
	return saved


func flush() -> bool:
	if not _enabled or not _active:
		return false
	if not is_instance_valid(_player) or not is_instance_valid(_save_manager):
		return false
	if _save_manager.get("current_snapshot") == null:
		return false
	var session_snapshot := _session_snapshot()
	if session_snapshot != null and _save_manager.get("current_snapshot") != session_snapshot:
		return false
	if not _save_manager.has_method("set_resume_state"):
		return false
	var current_position: Vector2 = _player.global_position
	var current_velocity := Vector2.ZERO
	if "velocity" in _player:
		current_velocity = Vector2(_player.get("velocity"))
	var saved := bool(_save_manager.call("set_resume_state", current_position, current_velocity, true))
	if saved:
		_last_position = current_position
		_last_velocity = current_velocity
	return saved


func _process(delta: float) -> void:
	if not _enabled or not _active:
		return
	_elapsed += delta
	if _elapsed < maxf(interval_seconds, 0.01):
		return
	_elapsed = 0.0
	capture_now()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_close_flushed = flush()


func _exit_tree() -> void:
	if not _close_flushed:
		flush()


func _resolve_sources() -> void:
	_player = get_node_or_null(player_path)
	_session = get_node_or_null(session_path)
	_save_manager = get_node_or_null(save_manager_path)
	_settings = get_node_or_null(settings_path)


func _connect_sources() -> void:
	if is_instance_valid(_settings) and _settings.has_signal("settings_changed"):
		var settings_callback := Callable(self, "_on_settings_changed")
		if not _settings.is_connected("settings_changed", settings_callback):
			_settings.connect("settings_changed", settings_callback)
	if is_instance_valid(_session):
		var ready_callback := Callable(self, "_on_world_ready")
		if _session.has_signal("world_ready") and not _session.is_connected("world_ready", ready_callback):
			_session.connect("world_ready", ready_callback)
		var failed_callback := Callable(self, "_on_world_start_failed")
		if _session.has_signal("world_start_failed") and not _session.is_connected("world_start_failed", failed_callback):
			_session.connect("world_start_failed", failed_callback)


func _refresh_enabled() -> void:
	var next_enabled := (
		is_instance_valid(_settings)
		and _settings.has_method("is_realtime_save_enabled")
		and bool(_settings.call("is_realtime_save_enabled"))
	)
	if next_enabled == _enabled:
		return
	_enabled = next_enabled
	_elapsed = 0.0
	if _enabled:
		if _active:
			capture_now()
		return
	_clear_resume()


func _clear_resume() -> void:
	_last_position = Vector2.INF
	_last_velocity = Vector2.INF
	if not is_instance_valid(_save_manager) or _save_manager.get("current_snapshot") == null:
		return
	var session_snapshot := _session_snapshot()
	if session_snapshot != null and _save_manager.get("current_snapshot") != session_snapshot:
		return
	if _save_manager.has_method("clear_resume_state"):
		_save_manager.call("clear_resume_state", true)


func _session_snapshot() -> RefCounted:
	if not is_instance_valid(_session):
		return null
	var value: Variant = _session.get("_active_snapshot")
	return value as RefCounted


func _on_settings_changed() -> void:
	_refresh_enabled()


func _on_world_ready() -> void:
	set_active(true)


func _on_world_start_failed(_errors: Array[String]) -> void:
	set_active(false)
