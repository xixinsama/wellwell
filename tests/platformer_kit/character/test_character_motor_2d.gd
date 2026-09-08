extends Node

const MOTOR_PATH := "res://addons/platformer_kit/character/motor/character_motor_2d.gd"
const CONTEXT_PATH := "res://addons/platformer_kit/character/motor/movement_context.gd"
const ENVIRONMENT_PATH := "res://addons/platformer_kit/character/environment/character_environment_snapshot.gd"
const INTENT_PATH := "res://addons/platformer_kit/character/input/character_intent.gd"
const PROFILE_PATH := "res://addons/platformer_kit/character/resources/movement_profile.gd"


func run() -> Array[String]:
	var failures: Array[String] = []
	for path: String in [MOTOR_PATH, CONTEXT_PATH, ENVIRONMENT_PATH]:
		if not ResourceLoader.exists(path, "Script"):
			failures.append("character motor script is missing: %s" % path)
	if not failures.is_empty():
		return failures
	_assert_horizontal_motion(failures)
	_assert_gravity_and_terminal_velocity(failures)
	_assert_jump_buffer(failures)
	_assert_coyote_time(failures)
	_assert_variable_jump(failures)
	return failures


func _assert_horizontal_motion(failures: Array[String]) -> void:
	var fixture := _fixture()
	fixture.intent.move_axis = 1.0
	fixture.environment.grounded = true
	fixture.motor.step(fixture.context, fixture.intent, fixture.environment, fixture.profile, 0.1)
	if not is_equal_approx(fixture.context.velocity.x, 85.0):
		failures.append("CharacterMotor2D used the wrong grounded acceleration")
	fixture.context.velocity.x = 100.0
	fixture.intent.move_axis = 0.0
	fixture.motor.step(fixture.context, fixture.intent, fixture.environment, fixture.profile, 0.05)
	if not is_equal_approx(fixture.context.velocity.x, 45.0):
		failures.append("CharacterMotor2D used the wrong grounded deceleration")
	fixture.context.velocity.x = 0.0
	fixture.intent.move_axis = 1.0
	fixture.environment.grounded = false
	fixture.motor.step(fixture.context, fixture.intent, fixture.environment, fixture.profile, 0.1)
	if not is_equal_approx(fixture.context.velocity.x, 60.0):
		failures.append("CharacterMotor2D used the wrong air acceleration")


func _assert_gravity_and_terminal_velocity(failures: Array[String]) -> void:
	var fixture := _fixture()
	fixture.intent.jump_held = true
	fixture.motor.step(fixture.context, fixture.intent, fixture.environment, fixture.profile, 0.1)
	if not is_equal_approx(fixture.context.velocity.y, 76.0):
		failures.append("CharacterMotor2D used the wrong base gravity")
	fixture.context.velocity.y = 290.0
	fixture.motor.step(fixture.context, fixture.intent, fixture.environment, fixture.profile, 1.0)
	if not is_equal_approx(fixture.context.velocity.y, 300.0):
		failures.append("CharacterMotor2D exceeded terminal velocity")


func _assert_jump_buffer(failures: Array[String]) -> void:
	var fixture := _fixture()
	fixture.intent.jump_pressed = true
	fixture.intent.jump_held = true
	fixture.motor.step(fixture.context, fixture.intent, fixture.environment, fixture.profile, 0.01)
	if fixture.context.just_jumped or fixture.context.jump_buffer_remaining <= 0.0:
		failures.append("CharacterMotor2D did not buffer an airborne jump press")
	fixture.intent.jump_pressed = false
	fixture.environment.grounded = true
	fixture.motor.step(fixture.context, fixture.intent, fixture.environment, fixture.profile, 0.01)
	if not fixture.context.just_jumped or fixture.context.velocity.y >= 0.0:
		failures.append("CharacterMotor2D did not consume jump buffer on landing")
	if fixture.context.jump_buffer_remaining != 0.0 or fixture.context.coyote_remaining != 0.0:
		failures.append("CharacterMotor2D did not clear jump timers after jumping")


func _assert_coyote_time(failures: Array[String]) -> void:
	var fixture := _fixture()
	fixture.environment.grounded = true
	fixture.motor.step(fixture.context, fixture.intent, fixture.environment, fixture.profile, 0.01)
	fixture.environment.grounded = false
	fixture.intent.jump_pressed = true
	fixture.intent.jump_held = true
	fixture.motor.step(fixture.context, fixture.intent, fixture.environment, fixture.profile, 0.04)
	if not fixture.context.just_jumped or fixture.context.velocity.y >= 0.0:
		failures.append("CharacterMotor2D rejected a jump during coyote time")


func _assert_variable_jump(failures: Array[String]) -> void:
	var held := _fixture()
	held.context.velocity.y = -100.0
	held.intent.jump_held = true
	held.motor.step(held.context, held.intent, held.environment, held.profile, 0.05)
	var released := _fixture()
	released.context.velocity.y = -100.0
	released.intent.jump_held = false
	released.motor.step(released.context, released.intent, released.environment, released.profile, 0.05)
	if released.context.velocity.y <= held.context.velocity.y:
		failures.append("CharacterMotor2D did not increase gravity after jump release")


func _fixture() -> Dictionary:
	return {
		"motor": (load(MOTOR_PATH) as Script).new(),
		"context": (load(CONTEXT_PATH) as Script).new(),
		"environment": (load(ENVIRONMENT_PATH) as Script).new(),
		"intent": (load(INTENT_PATH) as Script).new(),
		"profile": (load(PROFILE_PATH) as Script).new(),
	}

