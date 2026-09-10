class_name WaypointMotionComponent2D
extends "res://addons/platformer_kit/platforms/components/platform_motion_component_2d.gd"

signal waypoint_reached(index: int)

enum LoopMode {
	PING_PONG,
	CYCLE,
}

@export var waypoints := PackedVector2Array([Vector2.ZERO, Vector2(64.0, 0.0)])
@export_range(0.01, 2000.0, 0.01, "or_greater") var travel_speed := 64.0
@export_range(0.0, 60.0, 0.01, "or_greater") var arrival_pause_seconds := 0.0
@export var loop_mode := LoopMode.PING_PONG
@export var autoplay := true

var _current_offset := Vector2.ZERO
var _current_index := 0
var _target_index := 1
var _direction := 1
var _pause_remaining := 0.0


func sample_velocity(delta: float) -> Vector2:
	if not enabled or not autoplay or delta <= 0.0 or not is_route_valid():
		return Vector2.ZERO
	if _pause_remaining > 0.0:
		_pause_remaining = maxf(_pause_remaining - delta, 0.0)
		return Vector2.ZERO
	var target := waypoints[_target_index]
	var to_target := target - _current_offset
	var distance := to_target.length()
	if distance <= 0.0001:
		_arrive_at_target()
		return Vector2.ZERO
	var displacement := to_target.limit_length(travel_speed * delta)
	_current_offset += displacement
	if displacement.length() >= distance - 0.0001:
		_current_offset = target
		_arrive_at_target()
	return displacement / delta


func reset_component() -> void:
	_current_offset = Vector2.ZERO
	_current_index = 0
	_target_index = 1
	_direction = 1
	_pause_remaining = 0.0


func is_route_valid() -> bool:
	if waypoints.size() < 2 or travel_speed <= 0.0 or not waypoints[0].is_zero_approx():
		return false
	for index: int in range(1, waypoints.size()):
		if waypoints[index].is_equal_approx(waypoints[index - 1]):
			return false
	return true


func get_current_waypoint_index() -> int:
	return _current_index


func get_current_offset() -> Vector2:
	return _current_offset


func get_pause_remaining() -> float:
	return _pause_remaining


func _arrive_at_target() -> void:
	_current_index = _target_index
	_pause_remaining = arrival_pause_seconds
	waypoint_reached.emit(_current_index)
	if loop_mode == LoopMode.CYCLE:
		_target_index = (_current_index + 1) % waypoints.size()
		return
	if _current_index == waypoints.size() - 1:
		_direction = -1
	elif _current_index == 0:
		_direction = 1
	_target_index = _current_index + _direction
