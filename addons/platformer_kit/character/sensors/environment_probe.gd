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
	snapshot.on_moving_platform = not snapshot.floor_velocity.is_zero_approx()
	snapshot.platform_id = _get_platform_id(body) if snapshot.grounded else StringName()
	return snapshot


func _get_platform_id(body: CharacterBody2D) -> StringName:
	var floor_dot := cos(body.floor_max_angle)
	for index: int in body.get_slide_collision_count():
		var collision := body.get_slide_collision(index)
		if collision == null or collision.get_normal().dot(body.up_direction) < floor_dot:
			continue
		var platform := collision.get_collider()
		if platform == null:
			continue
		if platform.has_method("get_platform_id"):
			return StringName(platform.call("get_platform_id"))
		if "platform_id" in platform:
			return StringName(platform.get("platform_id"))
	return StringName()
