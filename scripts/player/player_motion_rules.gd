class_name PlayerMotionRules
extends RefCounted

## Pure Celeste-shaped velocity math shared by PlayerController and its tests.

static func intent_direction(intent: RefCounted, facing: int) -> int:
	var axis := float(intent.get("move_axis")) if intent != null else 0.0
	if absf(axis) > 0.01:
		return 1 if axis > 0.0 else -1
	return 1 if facing >= 0 else -1


static func super_jump_velocity(profile: RefCounted, direction: int, ducking: bool) -> Vector2:
	var facing := 1.0 if direction >= 0 else -1.0
	if ducking:
		return Vector2(float(profile.get("hyper_jump_speed")) * facing, float(profile.get("hyper_jump_vertical")))
	return Vector2(float(profile.get("super_jump_speed")) * facing, float(profile.get("jump_speed")))


static func wall_jump_velocity(profile: RefCounted, direction: int) -> Vector2:
	var facing := 1.0 if direction >= 0 else -1.0
	return Vector2(float(profile.get("wall_jump_speed")) * facing, float(profile.get("jump_speed")))


static func wallbounce_velocity(profile: RefCounted, direction: int) -> Vector2:
	var facing := 1.0 if direction >= 0 else -1.0
	return Vector2(float(profile.get("wallbounce_speed")) * facing, float(profile.get("wallbounce_jump_speed")))


static func wall_slide_cap(profile: RefCounted, remaining: float) -> float:
	var duration := maxf(float(profile.get("wall_slide_time")), 0.0001)
	var progress := clampf(1.0 - remaining / duration, 0.0, 1.0)
	return lerpf(
		float(profile.get("wall_slide_start_speed")),
		float(profile.get("max_fall_speed")),
		progress
	)
