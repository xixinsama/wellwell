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
	_assert_eight_way_motion_override(failures)
	_assert_dash_charge_recharge(failures)
	_assert_try_start_dash(failures)
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


func _assert_eight_way_motion_override(failures: Array[String]) -> void:
	var fixture := _make_loadout()
	var loadout: Node = fixture[0]
	var controller: Node = fixture[1]
	loadout.call("grant_ability_definition", DEFAULT_DASH)
	var diagonal := Vector2(1, -1).normalized()
	var cases := [
		[Vector2(0, -1), Vector2(0, -1)],
		[Vector2(0, 1), Vector2(0, 1)],
		[Vector2(1, -1), diagonal],
		[Vector2(-1, 1), -diagonal],
		[Vector2.ZERO, Vector2(1, 0)],
	]
	for entry: Array in cases:
		var intent: RefCounted = INTENT.new()
		intent.call("press_action", &"dash")
		var input: Vector2 = entry[0]
		intent.set("move_axis", input.x)
		intent.set("vertical_axis", input.y)
		var result: Dictionary = loadout.call("get_motion_override", intent, ENVIRONMENT.new(), 1)
		var expected: Vector2 = entry[1] * float(DEFAULT_DASH.dash_speed)
		if not bool(result.get("active", false)):
			failures.append("player loadout did not activate an eight-way Dash for %s" % [input])
		elif not Vector2(result.get("velocity", Vector2.ZERO)).is_equal_approx(expected):
			failures.append(
				"eight-way Dash input %s produced %s instead of %s"
				% [input, result.get("velocity"), expected]
			)
		controller.call("cancel", &"dash")
		controller.call("tick", float(DEFAULT_DASH.cooldown_seconds))
		loadout.call("update_dash_recharge", true)
	loadout.free()


func _assert_dash_charge_recharge(failures: Array[String]) -> void:
	var fixture := _make_loadout()
	var loadout: Node = fixture[0]
	var controller: Node = fixture[1]
	loadout.call("grant_ability_definition", DEFAULT_DASH)
	var runtime: RefCounted = controller.call("get_runtime", &"dash")
	if runtime == null:
		failures.append("player loadout did not install a Dash runtime")
		loadout.free()
		return
	var intent: RefCounted = INTENT.new()
	intent.call("press_action", &"dash")
	intent.set("move_axis", 1.0)
	var result: Dictionary = loadout.call("get_motion_override", intent, ENVIRONMENT.new(), 1)
	if not bool(result.get("active", false)) or int(runtime.call("get_charges")) != 0:
		failures.append("player Dash did not spend its charge on the first dash")
	controller.call("cancel", &"dash")
	controller.call("tick", float(DEFAULT_DASH.cooldown_seconds))
	loadout.call("update_dash_recharge", false)
	var air_intent: RefCounted = INTENT.new()
	air_intent.call("press_action", &"dash")
	air_intent.set("move_axis", -1.0)
	var air_result: Dictionary = loadout.call("get_motion_override", air_intent, ENVIRONMENT.new(), 1)
	if bool(air_result.get("active", false)):
		failures.append("player Dash activated in mid-air with no charge left")
	# The controller calls this every frame while grounded or swimming, which is
	# how water makes the dash unlimited.
	loadout.call("update_dash_recharge", true)
	if int(runtime.call("get_charges")) != int(DEFAULT_DASH.get("max_charges")):
		failures.append("Dash recharge did not restore the charge count")
	var grounded_result: Dictionary = loadout.call("get_motion_override", air_intent, ENVIRONMENT.new(), 1)
	if not bool(grounded_result.get("active", false)):
		failures.append("Dash could not activate after a recharge")
	controller.call("cancel", &"dash")
	loadout.free()


func _assert_try_start_dash(failures: Array[String]) -> void:
	var fixture := _make_loadout()
	var loadout: Node = fixture[0]
	var controller: Node = fixture[1]
	loadout.call("grant_ability_definition", DEFAULT_DASH)
	var intent: RefCounted = INTENT.new()
	intent.call("press_action", &"dash")
	intent.set("move_axis", 1.0)
	if not bool(loadout.call("try_start_dash", intent, ENVIRONMENT.new(), 1)):
		failures.append("player loadout did not expose a dash start seam")
	var runtime: RefCounted = loadout.call("get_dash_runtime")
	if runtime == null:
		failures.append("player loadout did not expose the dash runtime")
	elif not is_equal_approx(float(runtime.call("get_end_speed")), 160.0):
		failures.append("player loadout lost the dash end-speed tuning")
	if bool(loadout.call("try_start_dash", INTENT.new(), ENVIRONMENT.new(), 1)):
		failures.append("player loadout started a dash without a dash press")
	controller.call("cancel", &"dash")
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
