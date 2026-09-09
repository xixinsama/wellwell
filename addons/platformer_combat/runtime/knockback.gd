class_name Knockback
extends Node

@export var decay_per_second := 800.0
var _velocity := Vector2.ZERO


func _physics_process(delta: float) -> void:
	tick(delta)


func apply(event: RefCounted) -> void:
	if event != null and event.get("data") != null:
		_velocity = Vector2(event.get("data").get("impulse"))


func tick(delta: float) -> Vector2:
	_velocity = _velocity.move_toward(Vector2.ZERO, maxf(delta, 0.0) * decay_per_second)
	return _velocity


func clear() -> void:
	_velocity = Vector2.ZERO


func get_velocity() -> Vector2:
	return _velocity
