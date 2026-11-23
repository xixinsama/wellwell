class_name PlatformMotionComponent2D
extends Node

@export var enabled := true


func sample_velocity(_delta: float) -> Vector2:
	return Vector2.ZERO


func blocks_on_collision() -> bool:
	return false


func on_motion_collision(_normal: Vector2) -> void:
	pass


func reset_component() -> void:
	pass
