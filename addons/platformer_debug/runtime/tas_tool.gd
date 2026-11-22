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
var _start_position := Vector2.ZERO
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
			_play()
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


func _resolve_player() -> void:
	var subject := get_node_or_null(player_path)
	if subject == null or not subject.has_method("set_input_source"):
		return
	_player = subject
	_base_source = (
		_player.call("get_input_source") as RefCounted
		if _player.has_method("get_input_source")
		else null
	)
	_tas = TAS_INPUT_SOURCE.new(_base_source)
	_player.call("set_input_source", _tas)
	_start_position = _player.global_position


func _toggle_record() -> void:
	if _tas == null:
		return
	if _tas.is_recording():
		_tas.stop_recording()
		_status = "recording stopped: %d frames" % _tas.get_frame_count()
		return
	_tas.stop()
	_reset_player()
	_start_position = _player.global_position
	_max_speed = 0.0
	_tas.start_recording()
	_status = "recording"


func _play() -> void:
	if _tas == null:
		return
	if not _tas.start_playback():
		_status = "nothing recorded"
		return
	_reset_player()
	_max_speed = 0.0
	_status = "playing %d frames" % _tas.get_frame_count()


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
	var payload := {
		"version": 1,
		"physics_ticks": Engine.physics_ticks_per_second,
		"start": [_start_position.x, _start_position.y],
		"frames": _tas.get_frames(),
	}
	var file := FileAccess.open(recording_path, FileAccess.WRITE)
	if file == null:
		_status = "save failed"
		return
	file.store_string(JSON.stringify(payload))
	_status = "saved %d frames" % _tas.get_frame_count()


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
	lines.append("F6 rec  F7 play  F8 clear")
	lines.append("F9 slow  F10 save  F11 load")
	_label.text = "\n".join(lines)


func _apply_visible() -> void:
	if _layer != null:
		_layer.visible = _visible
