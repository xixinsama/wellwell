class_name EnvironmentProbe
extends RefCounted

const SNAPSHOT := preload("res://addons/platformer_kit/character/environment/character_environment_snapshot.gd")


func capture(body: CharacterBody2D) -> CharacterEnvironmentSnapshot:
	var snapshot := SNAPSHOT.new() as CharacterEnvironmentSnapshot
	if body == null:
		return snapshot
	snapshot.grounded = body.is_on_floor()
	snapshot.ceiling = body.is_on_ceiling()
	var wall_normal := body.get_wall_normal() if body.is_on_wall() else Vector2.ZERO
	snapshot.wall_left = wall_normal.x > 0.0
	snapshot.wall_right = wall_normal.x < 0.0
	snapshot.floor_normal = body.get_floor_normal() if snapshot.grounded else Vector2.UP
	snapshot.floor_velocity = body.get_platform_velocity() if snapshot.grounded else Vector2.ZERO
	snapshot.lift_velocity = _get_lift_velocity(body) if snapshot.grounded else Vector2.ZERO
	snapshot.on_moving_platform = not snapshot.floor_velocity.is_zero_approx()
	snapshot.on_lift_platform = not snapshot.lift_velocity.is_zero_approx()
	var floor_body := _get_floor_body(body) if snapshot.grounded else null
	snapshot.platform_id = _get_platform_id(floor_body)
	return snapshot


func _get_lift_velocity(body: CharacterBody2D) -> Vector2:
	var platform := _get_floor_body(body)
	if platform == null:
		return Vector2.ZERO
	if platform.has_method("get_motion_velocity"):
		return Vector2(platform.call("get_motion_velocity"))
	var platform_velocity := body.get_platform_velocity()
	# A conveyor is a constant surface velocity, not a moving platform that
	# should donate momentum to a jump.
	if "constant_linear_velocity" in platform:
		return platform_velocity - Vector2(platform.get("constant_linear_velocity"))
	return platform_velocity


func _get_floor_body(body: CharacterBody2D) -> Node:
	var floor_dot := cos(body.floor_max_angle)
	for index: int in body.get_slide_collision_count():
		var collision := body.get_slide_collision(index)
		if collision == null or collision.get_normal().dot(body.up_direction) < floor_dot:
			continue
		return collision.get_collider() as Node
	return null


func _get_platform_id(platform: Node) -> StringName:
	if platform == null:
		return StringName()
	if platform.has_method("get_platform_id"):
		return StringName(platform.call("get_platform_id"))
	if "platform_id" in platform:
		return StringName(platform.get("platform_id"))
	return StringName()
