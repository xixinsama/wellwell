class_name PingPongMotionComponent2D
extends "res://addons/platformer_kit/platforms/components/platform_motion_component_2d.gd"

@export var travel_offset := Vector2(64.0, 0.0)
@export_range(0.01, 60.0, 0.01) var cycle_duration := 2.0
@export var autoplay := true

var _elapsed := 0.0
var _last_offset := Vector2.ZERO


func sample_velocity(delta: float) -> Vector2:
	if not enabled or not autoplay or delta <= 0.0 or cycle_duration <= 0.0:
		return Vector2.ZERO
	var previous_offset := _last_offset
	_elapsed = fmod(_elapsed + delta, cycle_duration)
	_last_offset = travel_offset * _phase_weight(_elapsed / cycle_duration)
	return (_last_offset - previous_offset) / delta


func reset_component() -> void:
	_elapsed = 0.0
	_last_offset = Vector2.ZERO


func _phase_weight(phase: float) -> float:
	return phase * 2.0 if phase <= 0.5 else (1.0 - phase) * 2.0
