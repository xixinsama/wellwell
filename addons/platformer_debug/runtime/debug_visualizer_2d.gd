class_name PlatformerDebugVisualizer2D
extends Node2D

const VALID_LAYERS: Array[StringName] = [&"collision", &"sensors", &"motor", &"identity"]

@export var collision_color := Color(0.2, 0.9, 0.7, 0.9)
@export var active_sensor_color := Color(1.0, 0.75, 0.2, 0.95)
@export var inactive_sensor_color := Color(0.45, 0.5, 0.55, 0.65)
@export var relative_velocity_color := Color(0.35, 0.85, 1.0, 0.95)
@export var platform_velocity_color := Color(1.0, 0.72, 0.2, 0.95)
@export var world_velocity_color := Color(0.55, 1.0, 0.45, 0.95)
@export_range(0.01, 1.0, 0.01) var velocity_draw_scale := 0.12

var _subject: Node
var _layers := {
	&"collision": true,
	&"sensors": true,
	&"motor": true,
	&"identity": true,
}


func bind_subject(subject: Node) -> void:
	_subject = subject
	queue_redraw()


func set_layer_enabled(layer: StringName, enabled: bool) -> bool:
	if layer not in VALID_LAYERS:
		return false
	_layers[layer] = enabled
	queue_redraw()
	return true


func is_layer_enabled(layer: StringName) -> bool:
	return bool(_layers.get(layer, false))


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var subject_2d := _subject as Node2D
	if subject_2d == null or not is_instance_valid(subject_2d):
		return
	var origin := to_local(subject_2d.global_position)
	if is_layer_enabled(&"collision"):
		_draw_collision_shapes(subject_2d)
	if is_layer_enabled(&"sensors") and subject_2d.has_method("get_debug_state"):
		_draw_sensors(origin, subject_2d.call("get_debug_state"))
	if is_layer_enabled(&"motor"):
		_draw_velocity_vectors(origin, get_velocity_vectors())


func get_velocity_vectors() -> Dictionary:
	if _subject == null or not is_instance_valid(_subject) or not _subject.has_method("get_debug_state"):
		return {"relative": Vector2.ZERO, "platform": Vector2.ZERO, "world": Vector2.ZERO}
	var state: Dictionary = _subject.call("get_debug_state")
	return {
		"relative": Vector2(state.get("relative_velocity", state.get("velocity", Vector2.ZERO))),
		"platform": Vector2(state.get("platform_velocity", Vector2.ZERO)),
		"world": Vector2(state.get("world_velocity", Vector2.ZERO)),
	}


func _draw_collision_shapes(subject: Node2D) -> void:
	for node: Node in subject.find_children("*", "CollisionShape2D", true, false):
		var collision := node as CollisionShape2D
		if collision == null or collision.disabled or collision.shape == null:
			continue
		var center := to_local(collision.global_position)
		if collision.shape is RectangleShape2D:
			var rectangle := collision.shape as RectangleShape2D
			draw_rect(Rect2(center - rectangle.size * 0.5, rectangle.size), collision_color, false, 1.0)
		elif collision.shape is CircleShape2D:
			var circle := collision.shape as CircleShape2D
			draw_arc(center, circle.radius, 0.0, TAU, 24, collision_color, 1.0)
		elif collision.shape is CapsuleShape2D:
			var capsule := collision.shape as CapsuleShape2D
			draw_rect(Rect2(center - Vector2(capsule.radius, capsule.height * 0.5), Vector2(capsule.radius * 2.0, capsule.height)), collision_color, false, 1.0)


func _draw_sensors(origin: Vector2, state: Dictionary) -> void:
	_draw_sensor_line(origin, Vector2.DOWN * 10.0, bool(state.get("on_floor", false)))
	_draw_sensor_line(origin, Vector2.UP * 10.0, bool(state.get("ceiling", false)))
	_draw_sensor_line(origin, Vector2.LEFT * 10.0, bool(state.get("wall_left", false)))
	_draw_sensor_line(origin, Vector2.RIGHT * 10.0, bool(state.get("wall_right", false)))


func _draw_sensor_line(origin: Vector2, offset: Vector2, active: bool) -> void:
	draw_line(origin, origin + offset, active_sensor_color if active else inactive_sensor_color, 1.0)


func _draw_velocity_vectors(origin: Vector2, vectors: Dictionary) -> void:
	_draw_velocity_vector(origin, Vector2(vectors.get("relative", Vector2.ZERO)), relative_velocity_color)
	_draw_velocity_vector(origin, Vector2(vectors.get("platform", Vector2.ZERO)), platform_velocity_color)
	_draw_velocity_vector(origin, Vector2(vectors.get("world", Vector2.ZERO)), world_velocity_color)


func _draw_velocity_vector(origin: Vector2, velocity: Vector2, color: Color) -> void:
	var offset := velocity * velocity_draw_scale
	if offset.length() > 64.0:
		offset = offset.normalized() * 64.0
	if offset.length_squared() < 1.0:
		return
	draw_line(origin, origin + offset, color, 1.5)
	draw_circle(origin + offset, 2.0, color)
