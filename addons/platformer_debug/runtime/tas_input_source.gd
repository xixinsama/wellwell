class_name TasInputSource
extends RefCounted

## Wraps the player's normal input source and records or replays one
## CharacterIntent per physics tick. It is deliberately independent of the
## player class: the tool only needs set_input_source()/get_input_source().

signal playback_finished

const CHARACTER_INTENT := preload("res://addons/platformer_kit/character/input/character_intent.gd")

var _base: RefCounted
var _frames: Array[Dictionary] = []
var _recording := false
var _playing := false
var _play_index := 0


func _init(base_source: RefCounted = null) -> void:
	_base = base_source


func get_intent() -> CHARACTER_INTENT:
	if _playing:
		if _play_index >= _frames.size():
			_playing = false
			playback_finished.emit()
			return CHARACTER_INTENT.new()
		var data: Dictionary = _frames[_play_index]
		_play_index += 1
		return _intent_from(data)
	var intent: CHARACTER_INTENT = (
		_base.call("get_intent") as CHARACTER_INTENT
		if _base != null
		else CHARACTER_INTENT.new()
	)
	if intent == null:
		intent = CHARACTER_INTENT.new()
	if _recording:
		_frames.append(_snapshot(intent))
	return intent


func start_recording() -> void:
	_frames.clear()
	_playing = false
	_play_index = 0
	_recording = true


func stop_recording() -> void:
	_recording = false


func start_playback() -> bool:
	if _frames.is_empty():
		return false
	_recording = false
	_playing = true
	_play_index = 0
	return true


func stop() -> void:
	_recording = false
	_playing = false


func clear() -> void:
	stop()
	_frames.clear()
	_play_index = 0


func is_recording() -> bool:
	return _recording


func is_playing() -> bool:
	return _playing


func get_frame_count() -> int:
	return _frames.size()


func get_play_index() -> int:
	return _play_index


func get_frames() -> Array[Dictionary]:
	return _frames.duplicate(true)


func set_frames(value: Array[Dictionary]) -> void:
	_frames = value.duplicate(true)
	_recording = false
	_playing = false
	_play_index = 0


func _snapshot(intent: CHARACTER_INTENT) -> Dictionary:
	return {
		"move_axis": float(intent.move_axis),
		"vertical_axis": float(intent.vertical_axis),
		"jump_pressed": bool(intent.jump_pressed),
		"jump_released": bool(intent.jump_released),
		"jump_held": bool(intent.jump_held),
		"fast_fall": bool(intent.fast_fall),
		"dash": bool(intent.is_action_pressed(&"dash")),
	}


func _intent_from(data: Dictionary) -> CHARACTER_INTENT:
	var intent := CHARACTER_INTENT.new()
	intent.move_axis = float(data.get("move_axis", 0.0))
	intent.vertical_axis = float(data.get("vertical_axis", 0.0))
	intent.jump_pressed = bool(data.get("jump_pressed", false))
	intent.jump_released = bool(data.get("jump_released", false))
	intent.jump_held = bool(data.get("jump_held", false))
	intent.fast_fall = bool(data.get("fast_fall", false))
	if bool(data.get("dash", false)):
		intent.press_action(&"dash")
	return intent
