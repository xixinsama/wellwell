extends Node

const INTENT_PATH := "res://addons/platformer_kit/character/input/character_intent.gd"


func run() -> Array[String]:
	if not ResourceLoader.exists(INTENT_PATH, "Script"):
		return ["CharacterIntent script is missing"]
	var failures: Array[String] = []
	var intent: RefCounted = (load(INTENT_PATH) as Script).new()
	if not "jump_held" in intent:
		return ["CharacterIntent is missing continuous jump-held state"]
	intent.set("move_axis", 0.75)
	intent.set("jump_pressed", true)
	intent.set("jump_released", true)
	intent.set("jump_held", true)
	intent.set("fast_fall", true)
	intent.call("clear_transient")
	if (
		not is_equal_approx(float(intent.get("move_axis")), 0.75)
		or not bool(intent.get("jump_held"))
		or not bool(intent.get("fast_fall"))
	):
		failures.append("CharacterIntent cleared continuous input state")
	if bool(intent.get("jump_pressed")) or bool(intent.get("jump_released")):
		failures.append("CharacterIntent retained transient jump input")
	return failures
