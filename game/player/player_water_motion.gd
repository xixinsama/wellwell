class_name PlayerWaterMotion
extends Node2D

## Buoyancy and swimming composed around the character body, in the same shape
## as LadderMotionComponent2D: PlayerController calls step() before the motor and
## skips the motor when the component claims the frame.
##
## The component only reads the active WaterField (group "water_field"): it asks
## for the surface under the body, turns the body rectangle into a submersion
## ratio and replaces the movement context velocity with water motion. Entering
## at speed pushes the body deeper and asks the field for a splash, so impact
## speed changes both the splash and how far the hero sinks.

signal swim_animation_requested(active: bool, direction: Vector2)

## Gravity is not cancelled outright: buoyancy wins below the surface, so the
## hero settles with roughly `gravity / buoyancy` of the body under water.
@export var buoyancy := 1400.0
@export var water_drag := 3.4
@export var swim_acceleration := 620.0
@export var swim_max_speed := 96.0
@export var vertical_swim_acceleration := 420.0
@export var dive_acceleration := 300.0
@export var surface_hop_speed := 250.0
## Extra downward speed per px/s of impact speed. 0.35 means a 300 px/s fall
## enters ~105 px/s faster than a gentle step in.
@export_range(0.0, 1.0, 0.01) var entry_depth_scale := 0.35
@export var min_splash_speed := 70.0
@export var splash_cooldown := 0.12
## Below this submersion the normal motor still drives the body, so shallow
## water does not fight walking.
@export_range(0.0, 0.5, 0.01) var min_submersion := 0.12
@export var body_shape_path := NodePath("../CollisionShape2D")

var _field: Node
var _body_shape: CollisionShape2D
var _body_half_size := Vector2(3.0, 3.0)
var _body_offset := Vector2.ZERO
var _submerged := 0.0
var _was_in_water := false
var _splash_timer := 0.0
var _last_animation_active := false


func _ready() -> void:
	_body_shape = get_node_or_null(body_shape_path) as CollisionShape2D
	if _body_shape != null:
		_body_offset = _body_shape.position
		var rectangle := _body_shape.shape as RectangleShape2D
		if rectangle != null:
			_body_half_size = rectangle.size * 0.5
	_field = _resolve_field()


func bind_field(field: Node) -> void:
	_field = field
	reset()


## A room can hold two water systems: the 1D column field and the 2D grid. Only
## one of them is bound at a time, so the component prefers a ready field and
## falls back to any field in the group.
func _resolve_field() -> Node:
	var fallback: Node = null
	for node: Node in get_tree().get_nodes_in_group(&"water_field"):
		if not is_instance_valid(node):
			continue
		if fallback == null:
			fallback = node
		if bool(node.call("is_ready")):
			return node
	return fallback


func reset() -> void:
	_submerged = 0.0
	_was_in_water = false
	_splash_timer = 0.0
	_emit_animation(false, Vector2.ZERO)


func is_in_water() -> bool:
	return _submerged >= min_submersion


func get_submersion() -> float:
	return _submerged


func step(context: RefCounted, intent: RefCounted, environment: RefCounted, profile: RefCounted, delta: float) -> bool:
	if context == null or intent == null or profile == null:
		_submerged = 0.0
		_was_in_water = false
		_emit_animation(false, Vector2.ZERO)
		return false
	if _field == null or not is_instance_valid(_field):
		_field = _resolve_field()
	_splash_timer = maxf(_splash_timer - maxf(delta, 0.0), 0.0)
	if _field == null or not bool(_field.call("is_ready")):
		_submerged = 0.0
		_was_in_water = false
		_emit_animation(false, Vector2.ZERO)
		return false
	var body := get_parent() as Node2D
	if body == null:
		return false
	var surface := _surface_at(body.global_position)
	if surface == INF:
		_submerged = 0.0
		_was_in_water = false
		_emit_animation(false, Vector2.ZERO)
		return false

	var body_top := body.global_position.y + _body_offset.y - _body_half_size.y
	var body_bottom := body.global_position.y + _body_offset.y + _body_half_size.y
	var body_height := maxf(body_bottom - body_top, 1.0)
	var water_height := clampf(body_bottom - maxf(surface, body_top), 0.0, body_height)
	var submerged := water_height / body_height
	var in_water := submerged >= min_submersion
	_submerged = submerged
	if not in_water:
		_was_in_water = false
		_emit_animation(false, Vector2.ZERO)
		return false

	var velocity := Vector2(context.get("velocity"))
	var impact := velocity.y
	if not _was_in_water and impact > min_splash_speed:
		_enter_water(body.global_position.x, impact)
		velocity.y += minf(impact, 320.0) * entry_depth_scale
	_was_in_water = true
	_emit_animation(true, Vector2(float(intent.get("move_axis")), float(intent.get("vertical_axis"))))

	# Buoyancy pushes up (negative y) with the submerged share of the body; the
	# rest of the body still falls. Drag is what makes it settle instead of
	# bouncing. Equilibrium submersion is gravity / buoyancy (~0.54).
	var gravity := float(profile.get("gravity"))
	velocity.y += (gravity - buoyancy * submerged) * maxf(delta, 0.0)
	var drag_weight := 1.0 - exp(-water_drag * maxf(delta, 0.0))
	velocity *= 1.0 - drag_weight

	var flow := _flow_at(body.global_position)
	if absf(flow) > 0.01:
		velocity.x += flow * maxf(delta, 0.0) * 1.4

	var axis := clampf(float(intent.get("move_axis")), -1.0, 1.0)
	if not is_zero_approx(axis):
		velocity.x += axis * swim_acceleration * maxf(delta, 0.0)
	var vertical := clampf(float(intent.get("vertical_axis")), -1.0, 1.0)
	if vertical < 0.0:
		velocity.y += vertical * vertical_swim_acceleration * maxf(delta, 0.0)
	elif vertical > 0.0:
		velocity.y += vertical * dive_acceleration * maxf(delta, 0.0)

	velocity.x = clampf(velocity.x, -swim_max_speed, swim_max_speed)
	velocity.y = clampf(velocity.y, -float(profile.get("max_fall_speed")), float(profile.get("max_fall_speed")))

	if bool(intent.get("jump_pressed")) and submerged <= 0.8:
		_surface_hop(body.global_position.x)
		velocity.y = -surface_hop_speed
		context.set("just_jumped", true)
		intent.set("jump_pressed", false)
		_clear_jump_timers(context)
	else:
		context.set("just_jumped", false)
		_clear_jump_timers(context)

	context.set("velocity", velocity)
	return true


func get_debug_state() -> Dictionary:
	return {
		"submerged": _submerged,
		"in_water": is_in_water(),
		"has_field": _field != null and is_instance_valid(_field),
	}


func _surface_at(point: Vector2) -> float:
	if _field.has_method("get_surface_y_at_point"):
		return float(_field.call("get_surface_y_at_point", point))
	return float(_field.call("get_surface_y_at", point.x))


func _flow_at(point: Vector2) -> float:
	if _field.has_method("get_flow_velocity_at_point"):
		return float(_field.call("get_flow_velocity_at_point", point))
	return float(_field.call("get_flow_velocity_at", point.x))


func _surface_hop(world_x: float) -> void:
	if _splash_timer > 0.0 or _field == null:
		return
	_splash_timer = splash_cooldown
	_field.call("request_splash", world_x, surface_hop_speed * 0.7)


func _enter_water(world_x: float, impact_speed: float) -> void:
	if _field == null:
		return
	_field.call("request_splash", world_x, impact_speed)
	_splash_timer = splash_cooldown


func _clear_jump_timers(context: RefCounted) -> void:
	context.set("jump_buffer_remaining", 0.0)
	context.set("coyote_remaining", 0.0)


func _emit_animation(active: bool, direction: Vector2) -> void:
	if active == _last_animation_active and not active:
		return
	_last_animation_active = active
	swim_animation_requested.emit(active, direction)
