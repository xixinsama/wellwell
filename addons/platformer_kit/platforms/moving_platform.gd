class_name MovingPlatform
extends AnimatableBody2D

@export var platform_id: StringName
@export var travel_offset := Vector2(64.0, 0.0)
@export_range(0.01, 60.0, 0.01) var cycle_duration := 2.0
@export var autoplay := true

var _origin := Vector2.ZERO
var _elapsed := 0.0
var _platform_velocity := Vector2.ZERO


func _ready() -> void:
	reset_motion(position)


func _physics_process(delta: float) -> void:
	if autoplay:
		advance_motion(delta)


func reset_motion(origin: Vector2) -> void:
	_origin = origin
	_elapsed = 0.0
	position = origin
	_platform_velocity = Vector2.ZERO


func advance_motion(delta: float) -> void:
	if delta <= 0.0 or cycle_duration <= 0.0:
		_platform_velocity = Vector2.ZERO
		return
	var previous := position
	_elapsed = fmod(_elapsed + delta, cycle_duration)
	var phase := _elapsed / cycle_duration
	var weight := phase * 2.0 if phase <= 0.5 else (1.0 - phase) * 2.0
	position = _origin + travel_offset * weight
	_platform_velocity = (position - previous) / delta


func get_platform_velocity() -> Vector2:
	return _platform_velocity


func get_platform_id() -> StringName:
	return platform_id
