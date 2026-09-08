class_name CharacterMotor2D
extends RefCounted

const MOVEMENT_CONTEXT := preload("res://addons/platformer_kit/character/motor/movement_context.gd")
const CHARACTER_INTENT := preload("res://addons/platformer_kit/character/input/character_intent.gd")
const ENVIRONMENT_SNAPSHOT := preload("res://addons/platformer_kit/character/environment/character_environment_snapshot.gd")
const MOVEMENT_PROFILE := preload("res://addons/platformer_kit/character/resources/movement_profile.gd")


func step(
	context: MOVEMENT_CONTEXT,
	intent: CHARACTER_INTENT,
	environment: ENVIRONMENT_SNAPSHOT,
	profile: MOVEMENT_PROFILE,
	delta: float
) -> void:
	if context == null or intent == null or environment == null or profile == null:
		return
	var step_delta := maxf(delta, 0.0)
	context.just_jumped = false
	_update_timers(context, intent, environment, profile, step_delta)
	_apply_horizontal(context, intent, environment, profile, step_delta)
	if environment.ceiling and context.velocity.y < 0.0:
		context.velocity.y = 0.0
	if context.jump_buffer_remaining > 0.0 and context.coyote_remaining > 0.0:
		context.velocity.y = profile.jump_speed
		context.jump_buffer_remaining = 0.0
		context.coyote_remaining = 0.0
		context.just_jumped = true
	_apply_vertical(context, intent, environment, profile, step_delta)


func _update_timers(
	context: MOVEMENT_CONTEXT,
	intent: CHARACTER_INTENT,
	environment: ENVIRONMENT_SNAPSHOT,
	profile: MOVEMENT_PROFILE,
	delta: float
) -> void:
	context.jump_buffer_remaining = (
		profile.jump_buffer_time
		if intent.jump_pressed
		else maxf(context.jump_buffer_remaining - delta, 0.0)
	)
	context.coyote_remaining = (
		profile.coyote_time
		if environment.grounded
		else maxf(context.coyote_remaining - delta, 0.0)
	)


func _apply_horizontal(
	context: MOVEMENT_CONTEXT,
	intent: CHARACTER_INTENT,
	environment: ENVIRONMENT_SNAPSHOT,
	profile: MOVEMENT_PROFILE,
	delta: float
) -> void:
	var axis := clampf(intent.move_axis, -1.0, 1.0)
	var target_speed := axis * profile.max_speed
	var has_input := not is_zero_approx(axis)
	var rate: float
	if environment.grounded:
		rate = profile.ground_acceleration if has_input else profile.ground_deceleration
	else:
		rate = profile.air_acceleration if has_input else profile.air_deceleration
	context.velocity.x = move_toward(context.velocity.x, target_speed, rate * delta)


func _apply_vertical(
	context: MOVEMENT_CONTEXT,
	intent: CHARACTER_INTENT,
	environment: ENVIRONMENT_SNAPSHOT,
	profile: MOVEMENT_PROFILE,
	delta: float
) -> void:
	if environment.grounded and context.velocity.y >= 0.0 and not context.just_jumped:
		context.velocity.y = 0.0
		return
	var gravity_scale := 1.0
	if context.velocity.y < 0.0 and not intent.jump_held:
		gravity_scale = profile.jump_cut_gravity_multiplier
	elif context.velocity.y > 0.0:
		gravity_scale = profile.fall_gravity_multiplier
		if intent.fast_fall:
			gravity_scale *= profile.fast_fall_multiplier
	context.velocity.y += profile.gravity * gravity_scale * delta
	context.velocity.y = minf(context.velocity.y, profile.max_fall_speed)
