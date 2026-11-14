class_name LadderMotionComponent2D
extends Node2D

signal climb_animation_requested(active: bool, direction: Vector2)

@export var body_shape_path := NodePath("../CollisionShape2D")

var _detector: Area2D
var _overlaps: Dictionary = {}
var _drop_latched := false
var _jump_active := false
var _last_active := false
var _last_direction := Vector2.ZERO


func _ready() -> void:
	var body_shape := get_node_or_null(body_shape_path) as CollisionShape2D
	if body_shape == null or body_shape.shape == null:
		push_warning("LadderMotion requires a valid player CollisionShape2D")
		return
	_detector = Area2D.new()
	_detector.name = "Detector"
	_detector.collision_layer = 0
	_detector.collision_mask = 4
	_detector.position = body_shape.position
	var detector_shape := CollisionShape2D.new()
	detector_shape.shape = body_shape.shape.duplicate()
	_detector.add_child(detector_shape)
	add_child(_detector)
	_detector.area_entered.connect(_on_area_entered)
	_detector.area_exited.connect(_on_area_exited)


func is_on_ladder() -> bool:
	for area: Object in _overlaps.keys():
		if not is_instance_valid(area):
			_overlaps.erase(area)
	return not _overlaps.is_empty()


func step(context: RefCounted, intent: RefCounted, environment: RefCounted, profile: RefCounted, delta: float) -> bool:
	return apply_motion(context, intent, profile, delta, is_on_ladder(), bool(environment.get("grounded")))


func apply_motion(context: RefCounted, intent: RefCounted, profile: RefCounted, delta: float, on_ladder: bool, grounded: bool) -> bool:
	if context == null or intent == null or profile == null:
		return false
	if not on_ladder:
		_drop_latched = false
		_jump_active = false
		_emit_animation(false, Vector2.ZERO)
		return false
	if grounded:
		_drop_latched = false
	if _drop_latched and float(intent.get("vertical_axis")) < 0.0:
		_drop_latched = false
	if _drop_latched:
		_prepare_drop(context, intent)
		return false
	if float(intent.get("vertical_axis")) > 0.0 and bool(intent.get("jump_pressed")):
		_drop_latched = true
		_prepare_drop(context, intent)
		return false
	if bool(intent.get("jump_pressed")):
		_jump_active = true
		context.set("velocity", Vector2(float(context.get("velocity").x), float(profile.get("jump_speed"))))
		context.set("just_jumped", true)
		_clear_jump_timers(context)
		_emit_animation(false, Vector2.ZERO)
		return true
	if _jump_active and bool(intent.get("jump_held")) and float(context.get("velocity").y) < 0.0:
		context.set("velocity", Vector2(float(context.get("velocity").x), float(context.get("velocity").y) + float(profile.get("gravity")) * maxf(delta, 0.0)))
		context.set("just_jumped", false)
		_clear_jump_timers(context)
		_emit_animation(false, Vector2.ZERO)
		return true
	_jump_active = false
	var direction := Vector2(clampf(float(intent.get("move_axis")), -1.0, 1.0), clampf(float(intent.get("vertical_axis")), -1.0, 1.0))
	if direction.length_squared() > 1.0:
		direction = direction.normalized()
	context.set("velocity", direction * float(profile.get("climb_speed")))
	context.set("just_jumped", false)
	_clear_jump_timers(context)
	_emit_animation(true, direction)
	return true


func reset() -> void:
	_drop_latched = false
	_jump_active = false
	_emit_animation(false, Vector2.ZERO)


func _prepare_drop(context: RefCounted, intent: RefCounted) -> void:
	_jump_active = false
	context.set("velocity", Vector2(float(context.get("velocity").x), maxf(float(context.get("velocity").y), 0.0)))
	context.set("just_jumped", false)
	_clear_jump_timers(context)
	intent.set("jump_pressed", false)
	intent.set("fast_fall", true)
	_emit_animation(false, Vector2.ZERO)


func _clear_jump_timers(context: RefCounted) -> void:
	context.set("jump_buffer_remaining", 0.0)
	context.set("coyote_remaining", 0.0)


func _emit_animation(active: bool, direction: Vector2) -> void:
	if active == _last_active and direction == _last_direction:
		return
	_last_active = active
	_last_direction = direction
	climb_animation_requested.emit(active, direction)


func _on_area_entered(area: Area2D) -> void:
	if area.is_in_group("ladder_zone"):
		_overlaps[area] = true


func _on_area_exited(area: Area2D) -> void:
	_overlaps.erase(area)
