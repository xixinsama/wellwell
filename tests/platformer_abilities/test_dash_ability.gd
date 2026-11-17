extends Node

const DEFINITION_PATH := "res://addons/platformer_abilities/abilities/dash/dash_ability_definition.gd"
const RUNTIME_PATH := "res://addons/platformer_abilities/abilities/dash/dash_ability_runtime.gd"
const DEFAULT_DASH_PATH := "res://addons/platformer_abilities/abilities/dash/default_dash.tres"
const CONTEXT := preload("res://addons/platformer_abilities/runtime/ability_context.gd")
const CONTROLLER_PATH := "res://addons/platformer_abilities/runtime/ability_controller.gd"


func run() -> Array[String]:
	var failures: Array[String] = []
	for path: String in [DEFINITION_PATH, RUNTIME_PATH, DEFAULT_DASH_PATH]:
		if not ResourceLoader.exists(path):
			failures.append("Dash resource is missing: %s" % path)
	if not failures.is_empty():
		return failures
	_assert_eight_directions(failures)
	_assert_deadzone_and_facing_fallback(failures)
	_assert_legacy_horizontal_mode(failures)
	_assert_charge_limit(failures)
	_assert_unlimited_charges(failures)
	_assert_duration_and_cooldown(failures)
	_assert_controller_ticks_in_physics(failures)
	return failures


func _make_definition(speed: float, duration: float) -> Resource:
	var definition: Resource = (load(DEFINITION_PATH) as Script).new()
	definition.dash_speed = speed
	definition.dash_duration = duration
	definition.eight_directional = true
	definition.direction_deadzone = 0.35
	definition.direction_snap_degrees = 45.0
	return definition


func _make_runtime(definition: Resource) -> RefCounted:
	var runtime: RefCounted = (load(RUNTIME_PATH) as Script).new()
	runtime.configure(definition)
	return runtime


func _assert_eight_directions(failures: Array[String]) -> void:
	var speed := 240.0
	var definition := _make_definition(speed, 0.2)
	var diagonal := Vector2(1, 1).normalized()
	var cases := [
		[Vector2.RIGHT, Vector2.RIGHT],
		[Vector2.LEFT, Vector2.LEFT],
		[Vector2.UP, Vector2.UP],
		[Vector2.DOWN, Vector2.DOWN],
		[Vector2(1, 1), diagonal],
		[Vector2(-1, 1), Vector2(-diagonal.x, diagonal.y)],
		[Vector2(-1, -1), -diagonal],
		[Vector2(1, -1), Vector2(diagonal.x, -diagonal.y)],
	]
	for entry: Array in cases:
		var runtime := _make_runtime(definition)
		var context: RefCounted = CONTEXT.new()
		context.data = {"direction": entry[0], "facing": 1}
		var expected: Vector2 = entry[1]
		if not runtime.activate(context):
			failures.append("Dash rejected direction input %s" % [entry[0]])
			continue
		var velocity: Vector2 = runtime.get_velocity_override()
		if not velocity.is_equal_approx(expected * speed):
			failures.append(
				"Dash direction %s produced velocity %s instead of %s"
				% [entry[0], velocity, expected * speed]
			)
		if absf(velocity.length() - speed) > 0.01:
			failures.append("Dash direction %s did not keep its speed" % [entry[0]])
		if not runtime.get_dash_direction().is_equal_approx(expected):
			failures.append("Dash did not expose its normalized direction for %s" % [entry[0]])
		if runtime.is_motion_overriding() == false:
			failures.append("active Dash did not expose a motion override")
		runtime.cancel()


func _assert_deadzone_and_facing_fallback(failures: Array[String]) -> void:
	var definition := _make_definition(240.0, 0.2)
	var runtime := _make_runtime(definition)
	var context: RefCounted = CONTEXT.new()
	context.data = {"direction": Vector2(0.2, 0.1), "facing": -1}
	if not runtime.activate(context):
		failures.append("Dash rejected a below-deadzone direction")
	elif not runtime.get_velocity_override().is_equal_approx(Vector2(-240, 0)):
		failures.append("Dash did not fall back to facing inside the direction deadzone")
	runtime.cancel()
	var neutral := _make_runtime(definition)
	var neutral_context: RefCounted = CONTEXT.new()
	neutral_context.data = {"direction": Vector2.ZERO, "facing": 1}
	if not neutral.activate(neutral_context):
		failures.append("Dash rejected an empty direction")
	elif not neutral.get_velocity_override().is_equal_approx(Vector2(240, 0)):
		failures.append("zero-direction Dash did not fall back to facing")
	if neutral.get_velocity_override().is_zero_approx():
		failures.append("zero-direction Dash produced no movement")


func _assert_legacy_horizontal_mode(failures: Array[String]) -> void:
	var definition := _make_definition(240.0, 0.2)
	definition.eight_directional = false
	var runtime := _make_runtime(definition)
	var context: RefCounted = CONTEXT.new()
	context.data = {"direction": Vector2(0, -1), "facing": 1}
	if not runtime.activate(context):
		failures.append("horizontal-only Dash rejected vertical input")
	elif not runtime.get_velocity_override().is_equal_approx(Vector2(240, 0)):
		failures.append("horizontal-only Dash did not ignore the vertical axis")


func _assert_charge_limit(failures: Array[String]) -> void:
	var definition := _make_definition(240.0, 0.2)
	definition.cooldown_seconds = 0.0
	definition.max_charges = 1
	var runtime := _make_runtime(definition)
	var context: RefCounted = CONTEXT.new()
	context.data = {"direction": Vector2.RIGHT, "facing": 1}
	if runtime.get_charges() != 1 or runtime.has_unlimited_charges():
		failures.append("Dash did not start with its configured charge")
	if not runtime.activate(context):
		failures.append("Dash could not spend its first charge")
	if runtime.get_charges() != 0:
		failures.append("Dash did not consume its charge")
	runtime.finish()
	if runtime.can_activate(context):
		failures.append("Dash activated again without a charge")
	if runtime.activate(context):
		failures.append("Dash activated in mid-air with no charge left")
	runtime.refill()
	if runtime.get_charges() != 1 or not runtime.can_activate(context):
		failures.append("Dash refill did not restore the charge")
	var default_definition: Resource = load(DEFAULT_DASH_PATH)
	if int(default_definition.get("max_charges")) != 1:
		failures.append("default Dash is not tuned to a single charge")


func _assert_unlimited_charges(failures: Array[String]) -> void:
	var definition := _make_definition(240.0, 0.2)
	definition.cooldown_seconds = 0.0
	definition.max_charges = 0
	var runtime := _make_runtime(definition)
	var context: RefCounted = CONTEXT.new()
	context.data = {"direction": Vector2.DOWN, "facing": 1}
	if not runtime.has_unlimited_charges():
		failures.append("Dash max_charges = 0 did not mean unlimited dashes")
	for index in 3:
		if not runtime.activate(context):
			failures.append("unlimited Dash refused activation %d" % index)
			break
		runtime.finish()


func _assert_duration_and_cooldown(failures: Array[String]) -> void:
	var definition := _make_definition(240.0, 0.2)
	definition.cooldown_seconds = 0.5
	var runtime := _make_runtime(definition)
	var context: RefCounted = CONTEXT.new()
	context.data = {"direction": Vector2.DOWN, "facing": 1}
	if not runtime.activate(context):
		failures.append("Dash runtime rejected a valid context")
	runtime.tick(0.19)
	if not runtime.active:
		failures.append("Dash expired before its configured duration")
	runtime.tick(0.01)
	if (
		runtime.active
		or runtime.is_motion_overriding()
		or runtime.get_velocity_override() != Vector2.ZERO
		or runtime.get_dash_direction() != Vector2.ZERO
	):
		failures.append("Dash retained its motion override after duration expiry")
	runtime.refill()
	if runtime.can_activate(context):
		failures.append("Dash ignored cooldown after finishing")
	runtime.tick(float(definition.cooldown_seconds))
	if not runtime.can_activate(context):
		failures.append("Dash did not become available after cooldown")
	var default_definition: Resource = load(DEFAULT_DASH_PATH)
	var default_runtime := _make_runtime(default_definition)
	if not default_runtime.activate(context):
		failures.append("default Dash could not activate")
	if not default_runtime.cancel() or default_runtime.is_motion_overriding():
		failures.append("cancelled Dash retained its motion override")
	default_runtime.refill()
	if default_runtime.can_activate(context):
		failures.append("Dash ignored cooldown after cancellation")
	default_runtime.tick(float(default_definition.cooldown_seconds))
	if not default_runtime.can_activate(context):
		failures.append("Dash did not become available after cooldown")


func _assert_controller_ticks_in_physics(failures: Array[String]) -> void:
	var source := FileAccess.get_file_as_string(CONTROLLER_PATH)
	if not source.contains("func _physics_process(delta: float)"):
		failures.append("AbilityController does not tick on physics frames")
	if source.contains("func _process(delta: float)"):
		failures.append("AbilityController still ticks on render frames")
