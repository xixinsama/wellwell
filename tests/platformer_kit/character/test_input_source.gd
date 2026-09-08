extends Node

const INTENT_PATH := "res://addons/platformer_kit/character/input/character_intent.gd"
const INPUT_SOURCE_PATH := "res://addons/platformer_kit/character/input/input_source.gd"
const PLAYER_INPUT_SOURCE_PATH := "res://addons/platformer_kit/character/input/player_input_source.gd"


func run() -> Array[String]:
	var failures: Array[String] = []
	for path: String in [INTENT_PATH, INPUT_SOURCE_PATH, PLAYER_INPUT_SOURCE_PATH]:
		if not ResourceLoader.exists(path, "Script"):
			failures.append("character input script is missing: %s" % path)
	if not failures.is_empty():
		return failures
	var source: RefCounted = (load(INPUT_SOURCE_PATH) as Script).new()
	var neutral: RefCounted = source.call("get_intent")
	if neutral == null or not is_zero_approx(float(neutral.get("move_axis"))):
		failures.append("InputSource did not return a neutral CharacterIntent")
	_assert_player_input_adapter(failures)
	return failures


func _assert_player_input_adapter(failures: Array[String]) -> void:
	var source: RefCounted = (load(PLAYER_INPUT_SOURCE_PATH) as Script).new()
	Input.action_press("move_right", 0.75)
	Input.action_press("move_down")
	Input.action_press("jump")
	var intent: RefCounted = source.call("get_intent")
	Input.action_release("move_right")
	Input.action_release("move_down")
	Input.action_release("jump")
	if intent == null or float(intent.get("move_axis")) <= 0.0:
		failures.append("PlayerInputSource did not translate horizontal input")
	if intent == null or not bool(intent.get("fast_fall")):
		failures.append("PlayerInputSource did not translate held fast-fall input")
	if intent == null or not "jump_held" in intent or not bool(intent.get("jump_held")):
		failures.append("PlayerInputSource did not translate held jump input")
