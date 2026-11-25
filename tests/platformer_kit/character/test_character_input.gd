extends Node

## Merged test suite. Every inner class below is one original test file,
## kept in its own class so fixtures and helper names stay isolated. Do not
## add logic here: split a class back into its own file when it grows.

## tests/platformer_kit/character/test_character_intent.gd
class CharacterIntentCase extends Node:
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
		if not intent.has_method("press_action") or not intent.has_method("is_action_pressed"):
			failures.append("CharacterIntent is missing generic transient actions")
			return failures
		if intent.call("press_action", &""):
			failures.append("CharacterIntent accepted an empty action")
		if not intent.call("press_action", &"dash") or not intent.call("is_action_pressed", &"dash"):
			failures.append("CharacterIntent did not record a named action")
		if intent.call("press_action", &"dash"):
			failures.append("CharacterIntent reported a duplicate action as newly pressed")
		intent.call("clear_transient")
		if intent.call("is_action_pressed", &"dash"):
			failures.append("CharacterIntent retained a generic transient action")
		return failures


## tests/platformer_kit/character/test_input_source.gd
class InputSourceCase extends Node:
	const INTENT_PATH := "res://addons/platformer_kit/character/input/character_intent.gd"
	const INPUT_SOURCE_PATH := "res://addons/platformer_kit/character/input/input_source.gd"
	const PLAYER_INPUT_SOURCE_PATH := "res://addons/platformer_kit/character/input/player_input_source.gd"
	const FAKE_PLAYER_INPUT_SOURCE := preload("res://tests/platformer_kit/character/fake_player_input_source.gd")


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
		var source: RefCounted = FAKE_PLAYER_INPUT_SOURCE.new()
		var neutral: RefCounted = (load(INPUT_SOURCE_PATH) as Script).new().call("get_intent")
		var test_action := &"test_ability_action"
		source.set("additional_actions", Array([test_action], TYPE_STRING_NAME, &"", null))
		source.set("pressed_actions", Array([test_action], TYPE_STRING_NAME, &"", null))
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
		if intent == null or not intent.has_method("is_action_pressed") or not intent.call("is_action_pressed", test_action):
			failures.append("PlayerInputSource did not capture a configured named action")
		Input.action_press("move_up")
		var up_intent: RefCounted = source.call("get_intent")
		Input.action_release("move_up")
		if up_intent == null or not "vertical_axis" in up_intent or not is_equal_approx(float(up_intent.get("vertical_axis")), -1.0):
			failures.append("PlayerInputSource did not translate move_up to negative vertical_axis")
		Input.action_press("move_down")
		var down_intent: RefCounted = source.call("get_intent")
		Input.action_release("move_down")
		if down_intent == null or not "vertical_axis" in down_intent or not is_equal_approx(float(down_intent.get("vertical_axis")), 1.0):
			failures.append("PlayerInputSource did not translate move_down to positive vertical_axis")
		if not "vertical_axis" in neutral:
			failures.append("CharacterIntent is missing vertical_axis")
		elif not is_zero_approx(float(neutral.get("vertical_axis"))):
			failures.append("neutral CharacterIntent must have zero vertical_axis")


## tests/platformer_kit/character/test_movement_profile.gd
class MovementProfileCase extends Node:
	const PROFILE_SCRIPT_PATH := "res://addons/platformer_kit/character/resources/movement_profile.gd"
	const DEFAULT_PROFILE_PATH := "res://addons/platformer_kit/character/resources/default_movement_profile.tres"

	const EXPECTED_VALUES := {
		"max_speed": 100.0,
		"ground_acceleration": 1000.0,
		"ground_deceleration": 1000.0,
		"air_acceleration": 650.0,
		"air_deceleration": 650.0,
		"run_reduce": 400.0,
		"air_multiplier": 0.65,
		"jump_speed": -120.0,
		"jump_h_boost": 40.0,
		"var_jump_time": 0.2,
		"gravity": 900.0,
		"half_gravity_threshold": 40.0,
		"max_fall_speed": 160.0,
		"fast_max_fall_speed": 240.0,
		"fast_max_accel": 300.0,
		"jump_buffer_time": 0.08,
		"coyote_time": 0.1,
		"climb_speed": 72.0,
		"wall_climb_speed": 45.0,
		"climb_down_speed": 80.0,
		"wall_jump_speed": 130.0,
		"wall_jump_force_time": 0.16,
		"wall_grab_lockout": 0.16,
		"wall_check_distance": 3.0,
		"wallbounce_check_distance": 5.0,
		"wallbounce_speed": 170.0,
		"wallbounce_jump_speed": -160.0,
		"wall_slide_start_speed": 20.0,
		"wall_slide_time": 1.2,
		"climb_jump_stamina": 27.5,
		"climb_jump_convert_time": 0.2,
		"max_stamina": 110.0,
		"stamina_grab_drain": 10.0,
		"stamina_climb_drain": 45.4545,
		"stamina_tired_threshold": 20.0,
		"dash_attack_time": 0.3,
		"super_jump_speed": 260.0,
		"hyper_jump_speed": 325.0,
		"hyper_jump_vertical": -60.0,
		"corner_correction": 4.0,
		"lift_x_cap": 250.0,
		"lift_y_cap": -130.0,
	}


	func run() -> Array[String]:
		if not ResourceLoader.exists(PROFILE_SCRIPT_PATH, "Script"):
			return ["MovementProfile script is missing"]
		if not ResourceLoader.exists(DEFAULT_PROFILE_PATH, "Resource"):
			return ["default MovementProfile resource is missing"]
		var failures: Array[String] = []
		var profile := ResourceLoader.load(DEFAULT_PROFILE_PATH, "Resource", ResourceLoader.CACHE_MODE_IGNORE)
		if profile == null:
			return ["default MovementProfile resource could not be loaded"]
		for property_name: String in EXPECTED_VALUES:
			if not property_name in profile:
				failures.append("MovementProfile is missing expected value: %s" % property_name)
				continue
			if not is_equal_approx(float(profile.get(property_name)), float(EXPECTED_VALUES[property_name])):
				failures.append("default MovementProfile changed current value: %s" % property_name)
		return failures


## tests/platformer_kit/character/test_character_sensors.gd
class CharacterSensorsCase extends Node:
	const SENSORS_PATH := "res://addons/platformer_kit/character/sensors/character_sensors.gd"
	const PROBE_PATH := "res://addons/platformer_kit/character/sensors/environment_probe.gd"
	const SNAPSHOT_PATH := "res://addons/platformer_kit/character/environment/character_environment_snapshot.gd"

	class FakeProbe extends RefCounted:
		var snapshot: RefCounted

		func capture(_body: CharacterBody2D) -> RefCounted:
			return snapshot


	func run() -> Array[String]:
		var failures: Array[String] = []
		var sensors_script := load(SENSORS_PATH) as Script
		var probe_script := load(PROBE_PATH) as Script
		var snapshot_script := load(SNAPSHOT_PATH) as Script
		if sensors_script == null or probe_script == null or snapshot_script == null:
			return ["character sensor scripts could not be loaded"]

		var body := CharacterBody2D.new()
		var probe := FakeProbe.new()
		var expected: RefCounted = snapshot_script.new()
		expected.grounded = true
		expected.ceiling = true
		expected.wall_left = true
		expected.wall_right = false
		expected.floor_normal = Vector2(0.25, -0.9682458)
		expected.floor_velocity = Vector2(48.0, 0.0)
		expected.on_moving_platform = true
		probe.snapshot = expected

		var sensors: RefCounted = sensors_script.new()
		sensors.set_probe(probe)
		var actual = sensors.capture(body)
		if actual == null:
			failures.append("CharacterSensors did not produce a snapshot")
		else:
			if not actual.grounded or not actual.ceiling or not actual.wall_left or actual.wall_right:
				failures.append("CharacterSensors lost floor, ceiling, or wall contact state")
			if not actual.floor_normal.is_equal_approx(expected.floor_normal):
				failures.append("CharacterSensors lost the captured floor normal")
			if actual.floor_velocity != expected.floor_velocity or not actual.on_moving_platform:
				failures.append("CharacterSensors lost moving-platform velocity")
		if sensors.get_snapshot() != actual:
			failures.append("CharacterSensors did not retain the current frame snapshot")
		body.free()
		return failures


func run() -> Array[String]:
	var failures: Array[String] = []
	failures.append_array(_run_case(CharacterIntentCase.new()))
	failures.append_array(_run_case(InputSourceCase.new()))
	failures.append_array(_run_case(MovementProfileCase.new()))
	failures.append_array(_run_case(CharacterSensorsCase.new()))
	return failures


func _run_case(test: Node) -> Array[String]:
	add_child(test)
	var result: Array = test.call("run")
	test.queue_free()
	var failures: Array[String] = []
	failures.assign(result)
	return failures
