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
	_assert_direction_speed_and_duration(failures)
	_assert_cooldown_and_cancellation(failures)
	_assert_controller_ticks_in_physics(failures)
	return failures


func _assert_direction_speed_and_duration(failures: Array[String]) -> void:
	var definition: Resource = (load(DEFINITION_PATH) as Script).new()
	definition.dash_speed = 240.0
	definition.dash_duration = 0.2
	definition.cooldown_seconds = 0.5
	var runtime: RefCounted = (load(RUNTIME_PATH) as Script).new()
	runtime.configure(definition)
	var context: RefCounted = CONTEXT.new()
	context.data = {"direction": Vector2(3, 4), "facing": -1}
	if not runtime.activate(context):
		failures.append("Dash runtime rejected a valid context")
	elif not runtime.is_motion_overriding():
		failures.append("active Dash did not expose a motion override")
	elif not runtime.get_velocity_override().is_equal_approx(Vector2(144, 192)):
		failures.append("Dash did not normalize direction at configured speed")
	runtime.tick(0.19)
	if not runtime.active:
		failures.append("Dash expired before its configured duration")
	runtime.tick(0.01)
	if runtime.active or runtime.is_motion_overriding() or runtime.get_velocity_override() != Vector2.ZERO:
		failures.append("Dash retained its motion override after duration expiry")


func _assert_cooldown_and_cancellation(failures: Array[String]) -> void:
	var definition: Resource = load(DEFAULT_DASH_PATH)
	var runtime: RefCounted = (load(RUNTIME_PATH) as Script).new()
	runtime.configure(definition)
	var context: RefCounted = CONTEXT.new()
	context.data = {"direction": Vector2.ZERO, "facing": -1}
	if not runtime.activate(context):
		failures.append("default Dash could not activate")
	elif runtime.get_velocity_override().x >= 0.0:
		failures.append("zero-direction Dash did not fall back to facing")
	if not runtime.cancel() or runtime.is_motion_overriding():
		failures.append("cancelled Dash retained its motion override")
	if runtime.can_activate(context):
		failures.append("Dash ignored cooldown after cancellation")
	runtime.tick(float(definition.cooldown_seconds))
	if not runtime.can_activate(context):
		failures.append("Dash did not become available after cooldown")


func _assert_controller_ticks_in_physics(failures: Array[String]) -> void:
	var source := FileAccess.get_file_as_string(CONTROLLER_PATH)
	if not source.contains("func _physics_process(delta: float)"):
		failures.append("AbilityController does not tick on physics frames")
	if source.contains("func _process(delta: float)"):
		failures.append("AbilityController still ticks on render frames")
