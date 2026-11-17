class_name ElevatorMotionComponent2D
extends "res://addons/platformer_kit/platforms/components/platform_motion_component_2d.gd"

## An elevator that only moves when a rider steps on it.
##
## The platform idles at its authored position. A rider trigger on the platform
## calls [method activate]; the elevator rises to [member travel], waits, and
## returns by itself. A second rider can board at the top to ride it back down.
## This keeps a lift from wandering away while the player is still walking to it.

signal arrived_bottom()
signal arrived_top()

enum State {
	IDLE,
	MOVING_UP,
	WAITING_TOP,
	MOVING_DOWN,
	WAITING_BOTTOM,
}

@export var travel := Vector2(0.0, -104.0)
@export_range(1.0, 2000.0, 1.0, "or_greater") var speed := 56.0
@export_range(0.0, 10.0, 0.01) var top_wait_seconds := 1.4
@export_range(0.0, 10.0, 0.01) var bottom_wait_seconds := 0.4

var _state := State.IDLE
var _offset := Vector2.ZERO
var _timer := 0.0


## Called by a rider trigger. Ignored while the platform is away.
func activate() -> bool:
	if _state != State.IDLE and _state != State.WAITING_BOTTOM:
		return false
	_state = State.MOVING_UP
	_timer = 0.0
	return true


func is_waiting_for_rider() -> bool:
	return _state == State.IDLE or _state == State.WAITING_BOTTOM


func get_offset() -> Vector2:
	return _offset


func get_state_name() -> String:
	return State.keys()[_state]


func sample_velocity(delta: float) -> Vector2:
	if not enabled or delta <= 0.0:
		return Vector2.ZERO
	match _state:
		State.IDLE:
			return Vector2.ZERO
		State.WAITING_BOTTOM:
			_timer = maxf(_timer - delta, 0.0)
			if _timer <= 0.0:
				_state = State.IDLE
			return Vector2.ZERO
		State.MOVING_UP:
			return _move_toward(travel, delta)
		State.WAITING_TOP:
			_timer = maxf(_timer - delta, 0.0)
			if _timer <= 0.0:
				_state = State.MOVING_DOWN
			return Vector2.ZERO
		State.MOVING_DOWN:
			return _move_toward(Vector2.ZERO, delta)
	return Vector2.ZERO


func blocks_on_collision() -> bool:
	return false


func reset_component() -> void:
	_state = State.IDLE
	_offset = Vector2.ZERO
	_timer = 0.0


func _move_toward(target: Vector2, delta: float) -> Vector2:
	var to_target := target - _offset
	var distance := to_target.length()
	if distance <= 0.0001:
		_offset = target
		_arrive()
		return Vector2.ZERO
	var step := minf(speed * delta, distance)
	_offset += to_target.normalized() * step
	if step >= distance - 0.0001:
		_offset = target
		_arrive()
	return to_target.normalized() * speed


func _arrive() -> void:
	match _state:
		State.MOVING_UP:
			_state = State.WAITING_TOP
			_timer = top_wait_seconds
			arrived_top.emit()
		State.MOVING_DOWN:
			_state = State.WAITING_BOTTOM
			_timer = bottom_wait_seconds
			arrived_bottom.emit()
