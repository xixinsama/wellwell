extends Node

const LOADOUT_PATH := "res://game/player/player_ability_loadout.gd"
const CONTROLLER := preload("res://addons/platformer_abilities/runtime/ability_controller.gd")
const PROGRESSION := preload("res://addons/metroidvania_kit/progression/progression_context.gd")
const INTENT := preload("res://addons/platformer_kit/character/input/character_intent.gd")
const ENVIRONMENT := preload("res://addons/platformer_kit/character/environment/character_environment_snapshot.gd")
const DEFAULT_DASH := preload("res://addons/platformer_abilities/abilities/dash/default_dash.tres")


func run() -> Array[String]:
	var failures: Array[String] = []
	if not ResourceLoader.exists(LOADOUT_PATH, "Script"):
		return ["reference player ability loadout is missing"]
	_assert_progression_and_runtime_stay_synchronized(failures)
	_assert_dash_motion_override(failures)
	if not InputMap.has_action(&"dash"):
		failures.append("reference game has no dash input action")
	return failures


func _assert_progression_and_runtime_stay_synchronized(failures: Array[String]) -> void:
	var fixture := _make_loadout()
	var loadout: Node = fixture[0]
	var controller: Node = fixture[1]
	var progression: RefCounted = PROGRESSION.new()
	if not loadout.call("bind_progression", progression):
		failures.append("player loadout rejected ProgressionContext")
	if not loadout.call("grant_ability_definition", DEFAULT_DASH):
		failures.append("player loadout rejected the default Dash definition")
	if not progression.call("has_ability", &"dash") or not controller.call("has_ability", &"dash"):
		failures.append("granting Dash did not update progression and runtime together")
	if not loadout.call("grant_ability_definition", DEFAULT_DASH):
		failures.append("player loadout did not confirm duplicate Dash ownership")
	if controller.call("ability_ids") != [&"dash"]:
		failures.append("duplicate Dash grant created duplicate runtime state")
	progression.call("revoke_ability", &"dash")
	loadout.call("synchronize_unlocked_abilities")
	if controller.call("has_ability", &"dash"):
		failures.append("player loadout retained Dash after restoring locked progression")
	progression.call("grant_ability", &"dash")
	loadout.call("synchronize_unlocked_abilities")
	if not controller.call("has_ability", &"dash"):
		failures.append("player loadout did not reinstall restored Dash progression")
	loadout.free()


func _assert_dash_motion_override(failures: Array[String]) -> void:
	var fixture := _make_loadout()
	var loadout: Node = fixture[0]
	var controller: Node = fixture[1]
	loadout.call("grant_ability_definition", DEFAULT_DASH)
	var intent: RefCounted = INTENT.new()
	intent.call("press_action", &"dash")
	intent.set("move_axis", -1.0)
	var result: Dictionary = loadout.call("get_motion_override", intent, ENVIRONMENT.new(), 1)
	if not bool(result.get("active", false)):
		failures.append("player loadout did not activate Dash from CharacterIntent")
	elif not Vector2(result.get("velocity", Vector2.ZERO)).is_equal_approx(Vector2(-DEFAULT_DASH.dash_speed, 0)):
		failures.append("player loadout returned the wrong Dash velocity override")
	controller.call("cancel", &"dash")
	var neutral_result: Dictionary = loadout.call("get_motion_override", INTENT.new(), ENVIRONMENT.new(), 1)
	if not neutral_result.is_empty():
		failures.append("player loadout overrode motion while Dash was inactive")
	loadout.free()


func _make_loadout() -> Array[Node]:
	var loadout: Node = (load(LOADOUT_PATH) as Script).new()
	loadout.name = "AbilityLoadout"
	loadout.set("ability_definitions", Array([DEFAULT_DASH], TYPE_OBJECT, &"Resource", null))
	var controller: Node = CONTROLLER.new()
	controller.name = "AbilityController"
	loadout.add_child(controller)
	add_child(loadout)
	return [loadout, controller]
