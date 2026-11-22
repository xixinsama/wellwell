extends Node

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
