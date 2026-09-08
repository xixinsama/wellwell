class_name FallingPlatform
extends AnimatableBody2D

@export var platform_id: StringName
@export var gravity := 900.0
@export var terminal_velocity := 900.0
@export var active := false

var _platform_velocity := Vector2.ZERO


func _physics_process(delta: float) -> void:
	advance_motion(delta)


func activate() -> void:
	active = true


func reset_platform(position_value: Vector2) -> void:
	position = position_value
	active = false
	_platform_velocity = Vector2.ZERO


func advance_motion(delta: float) -> void:
	if not active or delta <= 0.0:
		return
	_platform_velocity.y = minf(_platform_velocity.y + gravity * delta, terminal_velocity)
	position += _platform_velocity * delta


func get_platform_velocity() -> Vector2:
	return _platform_velocity


func get_platform_id() -> StringName:
	return platform_id
