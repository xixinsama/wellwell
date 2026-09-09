class_name PlatformBody2D
extends AnimatableBody2D

signal motion_collided(normal: Vector2)
signal platform_reset(position: Vector2)

@export var platform_id := StringName()
@export var autoplay := true

var _reset_position := Vector2.ZERO
var _motion_velocity := Vector2.ZERO


func _ready() -> void:
	sync_to_physics = false
	_reset_position = position
	_reset_components()


func _physics_process(delta: float) -> void:
	if autoplay:
		advance_motion(delta)


func advance_motion(delta: float) -> void:
	if delta <= 0.0:
		_motion_velocity = Vector2.ZERO
		return
	var components: Array[Node] = _get_motion_components()
	var requested_velocity := Vector2.ZERO
	var collision_enabled := false
	for component: Node in components:
		requested_velocity += Vector2(component.call("sample_velocity", delta))
		collision_enabled = collision_enabled or bool(component.call("blocks_on_collision"))
	var requested_motion := requested_velocity * delta
	var actual_motion := requested_motion
	if collision_enabled and not requested_motion.is_zero_approx():
		var collision := move_and_collide(requested_motion)
		if collision != null:
			actual_motion = collision.get_travel()
			var normal := collision.get_normal()
			for component: Node in components:
				component.call("on_motion_collision", normal)
			motion_collided.emit(normal)
	else:
		position += requested_motion
	_motion_velocity = actual_motion / delta


func reset_platform(position_value: Vector2 = Vector2.INF) -> void:
	position = _reset_position if position_value == Vector2.INF else position_value
	_reset_position = position
	_motion_velocity = Vector2.ZERO
	_reset_components()
	for child: Node in get_children():
		if child.has_method("reset_component") and not child.has_method("sample_velocity"):
			child.call("reset_component")
	platform_reset.emit(position)


func get_motion_velocity() -> Vector2:
	return _motion_velocity


func get_platform_velocity() -> Vector2:
	return _motion_velocity + constant_linear_velocity


func get_platform_id() -> StringName:
	return platform_id


func _get_motion_components() -> Array[Node]:
	var result: Array[Node] = []
	for child: Node in get_children():
		if child.has_method("sample_velocity") and child.has_method("blocks_on_collision"):
			result.append(child)
	return result


func _reset_components() -> void:
	for component: Node in _get_motion_components():
		component.call("reset_component")
