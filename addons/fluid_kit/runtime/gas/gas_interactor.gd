@tool
class_name GasInteractor
extends Node2D

## Attach this to any entity that should touch the gas field. It is a thin
## adapter over the Atmosphere runtime API, so game code stays free of shader
## details:
##
##   Push   drags the gas along a box the size of the entity (velocity comes from
##          the node's own movement). Good for pillars, pistons, moving platforms.
##   Emit   injects gas at the node with a backward initial velocity, so the trail
##          lags behind the entity. Good for characters, exhausts, walkers.
##   Blast  one-shot explosion at the node (call blast() or enable blast_on_ready).
##
## Only one Push and one Emit interactor can be active at a time: the gas field
## has a single mover slot and a single emitter slot. Vents (GasVent) are separate
## and support up to four at once.

enum Mode { PUSH, EMIT, BLAST }

@export var mode: Mode = Mode.PUSH:
	set(value):
		mode = value
		queue_redraw()

## Push: box half extents are box_size * 0.5 (pixels).
@export var box_size := Vector2(8.0, 8.0):
	set(value):
		box_size = value
		queue_redraw()

@export_range(2.0, 64.0, 1.0) var radius := 12.0:
	set(value):
		radius = value
		queue_redraw()

## Push: multiplier on the entity's measured velocity.
@export_range(0.0, 4.0, 0.05) var strength := 1.0

## Emit: gas injected per second.
@export_range(0.0, 8.0, 0.05) var emit_rate := 4.0

## Emit: which gas channel.
@export_enum("Heavy", "Neutral", "Light") var channel := 1

## Emit: initial velocity relative to the entity, in pixels per second.
@export_range(0.0, 260.0, 1.0) var backward_speed := 105.0

## Emit: fallback direction when the entity is not moving.
@export var emit_direction := Vector2.RIGHT

@export_group("Blast")
@export_range(8.0, 96.0, 1.0) var blast_radius := 34.0
@export_range(0.0, 600.0, 5.0) var blast_strength := 190.0
@export_range(0.0, 3.0, 0.05) var blast_density := 1.1
@export var blast_on_ready := false

var _atmosphere: Node
var _last_position := Vector2.ZERO
var _velocity := Vector2.ZERO


func _ready() -> void:
	add_to_group(&"gas_interactor")
	_last_position = global_position
	if blast_on_ready:
		blast()


## Fires a single explosion at the node's position.
func blast() -> void:
	_find_atmosphere()
	if _atmosphere != null:
		_atmosphere.call("trigger_explosion", global_position, blast_radius, blast_strength, blast_density)


func _process(delta: float) -> void:
	_find_atmosphere()
	if _atmosphere == null:
		return
	_velocity = (global_position - _last_position) / maxf(delta, 0.001)
	_last_position = global_position
	match mode:
		Mode.PUSH:
			_atmosphere.call("set_gas_mover", global_position, box_size * 0.5, _velocity * strength)
		Mode.EMIT:
			var direction := emit_direction
			if _velocity.length() > 1.0:
				direction = _velocity.normalized()
			_atmosphere.call(
				"set_gas_emitter",
				global_position,
				radius,
				emit_rate,
				-direction * backward_speed,
				float(channel)
			)


func _exit_tree() -> void:
	if _atmosphere == null:
		return
	match mode:
		Mode.PUSH:
			_atmosphere.call("clear_gas_mover")
		Mode.EMIT:
			_atmosphere.call("clear_gas_emitter")


func _find_atmosphere() -> void:
	if _atmosphere != null and is_instance_valid(_atmosphere):
		return
	_atmosphere = get_tree().get_first_node_in_group(&"atmosphere")


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var color := Color(0.4, 0.85, 1.0, 0.7)
	if mode == Mode.PUSH:
		var half := box_size * 0.5
		draw_rect(Rect2(-half, box_size), color, false, 1.0)
	elif mode == Mode.EMIT:
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 24, color, 1.0)
		draw_line(Vector2.ZERO, -emit_direction * radius, Color(color, 0.9), 1.0)
	else:
		draw_arc(Vector2.ZERO, blast_radius, 0.0, TAU, 24, color, 1.0)
