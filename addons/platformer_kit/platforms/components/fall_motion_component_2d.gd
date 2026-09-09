class_name FallMotionComponent2D
extends "res://addons/platformer_kit/platforms/components/platform_motion_component_2d.gd"

signal activated()
signal landed()
signal reset()

enum CollisionMode {
	STOP_ON_COLLISION,
	IGNORE_COLLISIONS,
}

@export var gravity := 900.0
@export var terminal_velocity := 900.0
@export_range(0.0, 10.0, 0.01) var activation_delay := 0.0
@export var start_active := false
@export var collision_mode := CollisionMode.STOP_ON_COLLISION

var _active := false
var _landed := false
var _delay_remaining := 0.0
var _fall_velocity := 0.0


func _ready() -> void:
	if start_active:
		activate()


func activate() -> void:
	if _active:
		return
	_active = true
	_landed = false
	_delay_remaining = activation_delay
	activated.emit()


func is_active() -> bool:
	return _active


func has_landed() -> bool:
	return _landed


func sample_velocity(delta: float) -> Vector2:
	if not enabled or not _active or delta <= 0.0:
		return Vector2.ZERO
	if _delay_remaining > 0.0:
		_delay_remaining = maxf(_delay_remaining - delta, 0.0)
		return Vector2.ZERO
	_fall_velocity = minf(_fall_velocity + gravity * delta, terminal_velocity)
	return Vector2(0.0, _fall_velocity)


func blocks_on_collision() -> bool:
	return enabled and _active and collision_mode == CollisionMode.STOP_ON_COLLISION


func on_motion_collision(normal: Vector2) -> void:
	if not blocks_on_collision() or _fall_velocity <= 0.0 or normal.dot(Vector2.UP) < 0.5:
		return
	_active = false
	_landed = true
	_fall_velocity = 0.0
	landed.emit()


func reset_component() -> void:
	_active = start_active
	_landed = false
	_delay_remaining = activation_delay if start_active else 0.0
	_fall_velocity = 0.0
	reset.emit()
