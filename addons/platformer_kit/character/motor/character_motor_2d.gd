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
	var can_ground_jump := (
		context.jump_buffer_remaining > 0.0
		and context.coyote_remaining > 0.0
	)
	var can_air_jump := (
		context.jump_buffer_remaining > 0.0
		and context.air_jump_available
		and not environment.grounded
	)
	if can_ground_jump or can_air_jump:
		_start_jump(context, intent, environment, profile, can_air_jump and not can_ground_jump)
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
	if environment.grounded:
		context.air_jump_available = false


func _start_jump(
	context: MOVEMENT_CONTEXT,
	intent: CHARACTER_INTENT,
	environment: ENVIRONMENT_SNAPSHOT,
	profile: MOVEMENT_PROFILE,
	used_air_jump: bool
) -> void:
	var axis := clampf(intent.move_axis, -1.0, 1.0)
	context.velocity.y = profile.jump_speed
	context.velocity.x += profile.jump_h_boost * axis
	context.velocity += _capped_lift(Vector2(environment.get("lift_velocity")), profile)
	context.max_fall_current = profile.max_fall_speed
	context.var_jump_remaining = profile.var_jump_time
	context.var_jump_speed = context.velocity.y
	context.jump_buffer_remaining = 0.0
	context.coyote_remaining = 0.0
	context.just_jumped = true
	if used_air_jump:
		context.air_jump_available = false


func _apply_horizontal(
	context: MOVEMENT_CONTEXT,
	intent: CHARACTER_INTENT,
	environment: ENVIRONMENT_SNAPSHOT,
	profile: MOVEMENT_PROFILE,
	delta: float
) -> void:
	var axis := clampf(intent.move_axis, -1.0, 1.0)
	var has_input := not is_zero_approx(axis)
	var target_speed := axis * profile.max_speed
	var rate: float
	if (
		has_input
		and absf(context.velocity.x) > profile.max_speed
		and signf(context.velocity.x) == signf(axis)
	):
		var friction_scale := 1.0 if environment.grounded else profile.air_multiplier
		rate = profile.run_reduce * friction_scale
	elif environment.grounded:
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
		context.max_fall_current = profile.max_fall_speed
		return
	var target_max := (
		profile.fast_max_fall_speed
		if intent.fast_fall
		else profile.max_fall_speed
	)
	context.max_fall_current = move_toward(
		context.max_fall_current,
		target_max,
		profile.fast_max_accel * delta
	)
	var gravity_scale := 1.0
	if absf(context.velocity.y) < profile.half_gravity_threshold and intent.jump_held:
		gravity_scale = 0.5
	context.velocity.y = move_toward(
		context.velocity.y,
		context.max_fall_current,
		profile.gravity * gravity_scale * delta
	)
	if context.var_jump_remaining <= 0.0:
		return
	if not intent.jump_held:
		context.var_jump_remaining = 0.0
		return
	context.velocity.y = minf(context.velocity.y, context.var_jump_speed)
	context.var_jump_remaining = maxf(context.var_jump_remaining - delta, 0.0)


func _capped_lift(value: Vector2, profile: MOVEMENT_PROFILE) -> Vector2:
	return Vector2(
		clampf(value.x, -profile.lift_x_cap, profile.lift_x_cap),
		clampf(value.y, profile.lift_y_cap, 0.0)
	)
