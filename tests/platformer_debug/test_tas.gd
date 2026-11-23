extends Node

## Merged test suite. Every inner class below is one original test file,
## kept in its own class so fixtures and helper names stay isolated. Do not
## add logic here: split a class back into its own file when it grows.

## tests/platformer_debug/test_tas_input_source.gd
class TasInputSourceCase extends Node:
	const TAS_SOURCE_PATH := "res://addons/platformer_debug/runtime/tas_input_source.gd"
	const TAS_SCENE_PATH := "res://addons/platformer_debug/runtime/tas_tool.tscn"
	const INTENT_PATH := "res://addons/platformer_kit/character/input/character_intent.gd"


	class FakeBase:
		extends RefCounted
		var intents: Array = []
		var index := 0

		func get_intent() -> RefCounted:
			if intents.is_empty():
				return null
			var value: RefCounted = intents[mini(index, intents.size() - 1)]
			index += 1
			return value


	func run() -> Array[String]:
		var failures: Array[String] = []
		var script := load(TAS_SOURCE_PATH) as Script
		if script == null:
			return ["TAS input source is missing"]
		_assert_round_trip(script, failures)
		if not ResourceLoader.exists(TAS_SCENE_PATH):
			failures.append("TAS tool scene is missing")
		else:
			var packed := load(TAS_SCENE_PATH) as PackedScene
			var instance := packed.instantiate() if packed != null else null
			if instance == null or instance.get_node_or_null("Layer/Panel/Margin/Content/Status") == null:
				failures.append("TAS tool scene is missing its status panel")
			if instance != null:
				instance.free()
		return failures


	func _assert_round_trip(script: Script, failures: Array[String]) -> void:
		var intent_script := load(INTENT_PATH) as Script
		var first: RefCounted = intent_script.new()
		first.move_axis = 1.0
		first.jump_pressed = true
		first.jump_held = true
		first.call("press_action", &"dash")
		var second: RefCounted = intent_script.new()
		second.move_axis = -1.0
		second.vertical_axis = -1.0
		second.fast_fall = false
		var base := FakeBase.new()
		base.intents = [first, second, second]
		var source: RefCounted = script.new(base)
		source.call("start_recording")
		for _index: int in range(3):
			source.call("get_intent")
		source.call("stop_recording")
		if int(source.call("get_frame_count")) != 3:
			failures.append("TAS did not record one frame per get_intent call")
		if not bool(source.call("start_playback")):
			failures.append("TAS refused to play a non-empty recording")
			return
		var played: Array[RefCounted] = []
		for _index: int in range(3):
			played.append(source.call("get_intent"))
		if not is_equal_approx(float(played[0].get("move_axis")), 1.0):
			failures.append("TAS did not replay horizontal input")
		if not bool(played[0].get("jump_pressed")) or not bool(played[0].get("jump_held")):
			failures.append("TAS did not replay jump edges")
		if not bool(played[0].call("is_action_pressed", &"dash")):
			failures.append("TAS did not replay the dash action")
		if not is_equal_approx(float(played[1].get("vertical_axis")), -1.0):
			failures.append("TAS did not replay vertical input")
		var end_intent: RefCounted = source.call("get_intent")
		if end_intent == null or bool(end_intent.get("jump_pressed")):
			failures.append("TAS did not return a neutral intent after playback")
		if bool(source.call("is_playing")):
			failures.append("TAS stayed in playback after the final frame")


## tests/platformer_debug/test_tas_tool_hotkeys.gd
class TasToolHotkeysCase extends Node:
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


func run() -> Array[String]:
	var failures: Array[String] = []
	failures.append_array(_run_case(TasInputSourceCase.new()))
	failures.append_array(_run_case(TasToolHotkeysCase.new()))
	return failures


func _run_case(test: Node) -> Array[String]:
	add_child(test)
	var result: Array = test.call("run")
	test.queue_free()
	var failures: Array[String] = []
	failures.assign(result)
	return failures
