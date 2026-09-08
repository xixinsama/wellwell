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
	return snapshot
