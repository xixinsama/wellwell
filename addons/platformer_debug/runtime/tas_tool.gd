class_name TasTool
extends Node

## Minimal input TAS for the debug overlay: record one CharacterIntent per
## physics tick, replay it, save/load JSON, and inspect the resulting speed.
## Hotkeys: F5 toggle UI, F6 record, F7 play, F8 clear, F9 slow-motion,
## F10 save, F11 load, F12 reset.

const TAS_INPUT_SOURCE := preload("res://addons/platformer_debug/runtime/tas_input_source.gd")

@export var player_path: NodePath = NodePath("../Player")
@export var start_visible := true
@export var slow_scale := 0.25
@export var recording_path := "user://tas_recording.json"

var _player: Node
var _base_source: RefCounted
var _tas: RefCounted
var _world_session: Node
var _world_runtime: Node
var _start_position := Vector2.ZERO
var _start_world_id := ""
var _start_room_id := ""
var _visible := true
var _slow := false
var _max_speed := 0.0
var _status := ""

@onready var _layer: CanvasLayer = get_node_or_null("Layer")
@onready var _label: Label = get_node_or_null("Layer/Panel/Margin/Content/Status")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_visible = start_visible
	_apply_visible()
	_resolve_player()


func _process(_delta: float) -> void:
	if _player == null:
		_resolve_player()
	if _tas == null:
		return
	_update_speed()
	_update_label()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	match key_event.keycode:
		KEY_F5:
			_visible = not _visible
			_apply_visible()
		KEY_F6:
			_toggle_record()
		KEY_F7:
			_toggle_playback()
		KEY_F8:
			_clear()
		KEY_F9:
			_toggle_slow()
		KEY_F10:
			_save()
		KEY_F11:
			_load()
		KEY_F12:
			_reset_player()
			_status = "reset"
		KEY_R:
			if key_event.ctrl_pressed:
				_toggle_record()
		KEY_P:
			if key_event.ctrl_pressed:
				_toggle_playback()
		KEY_S:
			if key_event.ctrl_pressed:
				_save()


func _resolve_player() -> void:
	var subject := get_node_or_null(player_path)
	if subject == null or not subject.has_method("set_input_source"):
		return
	_player = subject
	_resolve_world()
	_base_source = (
		_player.call("get_input_source") as RefCounted
		if _player.has_method("get_input_source")
		else null
	)
	_tas = TAS_INPUT_SOURCE.new(_base_source)
	if _tas.has_signal("playback_finished"):
		_tas.connect("playback_finished", Callable(self, "_on_playback_finished"))
	_player.call("set_input_source", _tas)
	_start_position = _player.global_position


func _resolve_world() -> void:
	if is_instance_valid(_world_session) and is_instance_valid(_world_runtime):
		return
	var node := get_parent()
	while node != null:
		if node.has_method("start_selected_snapshot") or node.has_method("get_last_start_errors"):
			_world_session = node
			break
		node = node.get_parent()
	if _world_session != null:
		_world_runtime = _world_session.get_node_or_null("WorldRuntime")


func _current_world_id() -> String:
	if is_instance_valid(_world_runtime):
		var runtime_world: Variant = _world_runtime.get("world_data")
		if runtime_world != null and "world_id" in runtime_world:
			return String(runtime_world.get("world_id"))
	if is_instance_valid(_world_session):
		var session_world: Variant = _world_session.get("world_data")
		if session_world != null and "world_id" in session_world:
			return String(session_world.get("world_id"))
	return ""


func _current_room_id() -> String:
	if is_instance_valid(_world_runtime) and _world_runtime.has_method("get_current_room_id"):
		return String(_world_runtime.call("get_current_room_id"))
	return ""


func _toggle_record() -> void:
	if _tas == null:
		return
	if _tas.is_recording():
		_tas.stop_recording()
		_status = "recording stopped: %d frames" % _tas.get_frame_count()
		return
	_tas.stop()
	_start_position = _player.global_position
	_start_world_id = _current_world_id()
	_start_room_id = _current_room_id()
	_max_speed = 0.0
	_tas.start_recording()
	_status = "recording"


func _toggle_playback() -> void:
	if _tas == null:
		return
	if _tas.is_playing():
		_tas.stop()
		_status = "playback stopped"
		return
	_play()


func _play() -> void:
	if _tas == null:
		return
	if not _replay_location_matches():
		_status = _replay_location_error()
		return
	if not _tas.start_playback():
		_status = "nothing recorded"
		return
	_reset_player()
	_max_speed = 0.0
	_status = "playing %d frames" % _tas.get_frame_count()


func _replay_location_matches() -> bool:
	if not _start_room_id.is_empty() and _current_room_id() != _start_room_id:
		return false
	if not _start_world_id.is_empty() and _current_world_id() != _start_world_id:
		return false
	return true


func _replay_location_error() -> String:
	if not _start_world_id.is_empty() and _current_world_id() != _start_world_id:
		return "replay starts in world %s" % _start_world_id
	return "replay starts in room %s" % _start_room_id


func _on_playback_finished() -> void:
	_status = "playback finished"


func _clear() -> void:
	if _tas == null:
		return
	_tas.clear()
	_max_speed = 0.0
	_status = "cleared"


func _toggle_slow() -> void:
	_slow = not _slow
	Engine.time_scale = slow_scale if _slow else 1.0
	_status = "slow %.2fx" % Engine.time_scale if _slow else "slow off"


func _save() -> void:
	if _tas == null:
		return
	if _tas.is_recording():
		_tas.stop_recording()
	var frame_count := int(_tas.get_frame_count())
	var payload := {
		"version": 1,
		"physics_ticks": Engine.physics_ticks_per_second,
		"start": [_start_position.x, _start_position.y],
		"world_id": _start_world_id,
		"room_id": _start_room_id,
		"frames": _tas.get_frames(),
	}
	if not _write_recording(payload):
		_status = "save failed"
		return
	_status = "saved %d frames" % frame_count


func _write_recording(payload: Dictionary) -> bool:
	var temporary := recording_path + ".tmp"
	var backup := recording_path + ".bak"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(payload))
	file.flush()
	file.close()
	var absolute_temporary := ProjectSettings.globalize_path(temporary)
	var absolute_target := ProjectSettings.globalize_path(recording_path)
	var absolute_backup := ProjectSettings.globalize_path(backup)
	if FileAccess.file_exists(backup):
		DirAccess.remove_absolute(absolute_backup)
	if FileAccess.file_exists(recording_path):
		if DirAccess.rename_absolute(absolute_target, absolute_backup) != OK:
			DirAccess.remove_absolute(absolute_temporary)
			return false
	if DirAccess.rename_absolute(absolute_temporary, absolute_target) != OK:
		if FileAccess.file_exists(backup):
			DirAccess.rename_absolute(absolute_backup, absolute_target)
		return false
	if FileAccess.file_exists(backup):
		DirAccess.remove_absolute(absolute_backup)
	return true


func _load() -> void:
	if _tas == null:
		return
	if not FileAccess.file_exists(recording_path):
		_status = "no recording file"
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(recording_path))
	if not (parsed is Dictionary):
		_status = "load failed"
		return
	var payload := parsed as Dictionary
	var raw_frames: Variant = payload.get("frames", [])
	if not (raw_frames is Array):
		_status = "load failed: frames"
		return
	var frames: Array[Dictionary] = []
	for entry: Variant in raw_frames:
		if entry is Dictionary:
			frames.append(entry as Dictionary)
	_tas.set_frames(frames)
	var start: Variant = payload.get("start", [])
	if start is Array and (start as Array).size() >= 2:
		_start_position = Vector2(float(start[0]), float(start[1]))
	_start_world_id = String(payload.get("world_id", _start_world_id))
	_start_room_id = String(payload.get("room_id", _start_room_id))
	_max_speed = 0.0
	_status = "loaded %d frames" % frames.size()


func _reset_player() -> void:
	if _player == null:
		return
	if _player.has_method("respawn_at"):
		_player.call("respawn_at", _start_position)
	elif _player is Node2D:
		(_player as Node2D).global_position = _start_position


func _update_speed() -> void:
	if _player == null or not _player.has_method("get_debug_state"):
		return
	var state: Dictionary = _player.call("get_debug_state")
	var world_velocity: Vector2 = state.get("world_velocity", Vector2.ZERO)
	_max_speed = maxf(_max_speed, world_velocity.length())


func _update_label() -> void:
	if _label == null:
		return
	var mode := "IDLE"
	if _tas.is_recording():
		mode = "REC"
	elif _tas.is_playing():
		mode = "PLAY"
	var debug: Dictionary = (
		_player.call("get_debug_state")
		if _player != null and _player.has_method("get_debug_state")
		else {}
	)
	var speed: float = Vector2(debug.get("world_velocity", Vector2.ZERO)).length()
	var state: int = int(debug.get("state", 0))
	var lines: Array[String] = [
		"TAS %s  %d / %d" % [mode, _tas.get_frame_count(), _tas.get_play_index()],
		"v %.0f  max %.0f  state %d" % [speed, _max_speed, state],
	]
	if not _status.is_empty():
		lines.append(_status)
	lines.append("Ctrl+R rec  Ctrl+P play")
	lines.append("Ctrl+S save  F6/F7/F10")
	lines.append("F8 clear  F9 slow  F11 load")
	_label.text = "\n".join(lines)


func _apply_visible() -> void:
	if _layer != null:
		_layer.visible = _visible
