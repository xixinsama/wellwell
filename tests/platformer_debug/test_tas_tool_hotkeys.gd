extends Node

const TAS_SCENE := preload("res://addons/platformer_debug/runtime/tas_tool.tscn")
const TAS_PANEL_SCENE := preload("res://addons/platformer_debug/runtime/tas_panel.tscn")
const TEST_RECORDING := "user://tas_hotkey_test.json"


class FakePlayer extends Node2D:
	var source: RefCounted
	var respawns: Array[Vector2] = []

	func set_input_source(value: RefCounted) -> bool:
		source = value
		return true

	func get_input_source() -> RefCounted:
		return source

	func respawn_at(target: Vector2) -> void:
		global_position = target
		respawns.append(target)


func run() -> Array[String]:
	var failures: Array[String] = []
	_remove_recording()
	var player := FakePlayer.new()
	player.name = "Player"
	add_child(player)
	var panel := TAS_PANEL_SCENE.instantiate() as Control
	add_child(panel)
	var tool := TAS_SCENE.instantiate() as Node
	tool.set("player_path", NodePath("../Player"))
	tool.set("recording_path", TEST_RECORDING)
	add_child(tool)
	var tas: RefCounted = tool.get("_tas")
	if tas == null:
		failures.append("TAS tool did not bind a fake player")
		_cleanup(tool, player, panel)
		return failures
	tool.call("_resolve_panel")
	if tool.get("_external_panel") != panel:
		failures.append("TAS tool did not bind the HUD-space TAS panel")
	if not panel.visible:
		failures.append("TAS tool did not show the HUD-space panel")
	var internal_layer := tool.get_node_or_null("Layer") as CanvasLayer
	if internal_layer != null and internal_layer.visible:
		failures.append("TAS tool kept its SubViewport-space panel visible")

	_press_key(tool, KEY_F5, false)
	if panel.visible:
		failures.append("F5 did not hide the HUD-space TAS panel")
	_press_key(tool, KEY_F5, false)
	if not panel.visible:
		failures.append("F5 did not restore the HUD-space TAS panel")

	_press_key(tool, KEY_R, true)
	if not bool(tas.call("is_recording")):
		failures.append("Ctrl+R did not start recording")
	player.source.call("get_intent")
	_press_key(tool, KEY_R, true)
	if bool(tas.call("is_recording")):
		failures.append("Ctrl+R did not stop recording")
	if int(tas.call("get_frame_count")) != 1:
		failures.append("Ctrl+R recording did not capture the tick")

	_press_key(tool, KEY_S, true)
	if not FileAccess.file_exists(TEST_RECORDING):
		failures.append("Ctrl+S did not write the recording")
	else:
		var payload: Variant = JSON.parse_string(FileAccess.get_file_as_string(TEST_RECORDING))
		if not payload is Dictionary or not (payload as Dictionary).has("room_id"):
			failures.append("Ctrl+S recording payload is missing room metadata")

	_press_key(tool, KEY_P, true)
	if not bool(tas.call("is_playing")):
		failures.append("Ctrl+P did not start playback")
	_press_key(tool, KEY_P, true)
	if bool(tas.call("is_playing")):
		failures.append("Ctrl+P did not stop playback")

	_press_key(tool, KEY_F6, false)
	if not bool(tas.call("is_recording")):
		failures.append("F6 stopped working after the Ctrl shortcuts were added")

	_cleanup(tool, player, panel)
	_remove_recording()
	return failures


func _press_key(tool: Node, keycode: Key, ctrl: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.ctrl_pressed = ctrl
	event.pressed = true
	tool.call("_unhandled_input", event)


func _cleanup(tool: Node, player: Node, panel: Node = null) -> void:
	tool.free()
	player.free()
	if panel != null:
		panel.free()


func _remove_recording() -> void:
	if FileAccess.file_exists(TEST_RECORDING):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_RECORDING))
