@tool
class_name GasTrailWalker
extends Node2D

## A 1x1-cell block that keeps walking a square loop and leaves a gas trail.
##
## Every frame it tells the room's Atmosphere to inject gas at its own position
## with a velocity opposite to its movement, so the trail lags behind the block.
## The room's GasField (`decay`) is what makes the trail dissolve over time.

@export var square_size := Vector2(150.0, 78.0)
@export_range(10.0, 240.0, 1.0) var speed := 70.0
@export_range(2.0, 32.0, 1.0) var emit_radius := 9.0
@export_range(0.0, 8.0, 0.05) var emit_rate := 2.6
@export_range(0.0, 260.0, 1.0) var backward_speed := 95.0
@export_enum("Heavy", "Neutral", "Light") var channel := 1
@export var block_color := Color(0.7, 0.74, 0.82, 1.0)

var _atmosphere: Node
var _distance := 0.0
var _offset := Vector2.ZERO
var _direction := Vector2.RIGHT


func _ready() -> void:
	add_to_group(&"gas_trail_walker")
	_atmosphere = get_tree().get_first_node_in_group(&"atmosphere")


func _process(delta: float) -> void:
	_advance(delta)
	if _atmosphere == null or not is_instance_valid(_atmosphere):
		_atmosphere = get_tree().get_first_node_in_group(&"atmosphere")
	if _atmosphere != null:
		var world := global_position + _offset
		_atmosphere.call(
			"set_gas_emitter",
			world,
			emit_radius,
			emit_rate,
			-_direction * backward_speed,
			float(channel)
		)
	queue_redraw()


func _advance(delta: float) -> void:
	var half := square_size * 0.5
	var perimeter := 2.0 * (square_size.x + square_size.y)
	_distance = fmod(_distance + speed * delta, perimeter)
	var d := _distance
	if d < square_size.x:
		_offset = Vector2(-half.x + d, -half.y)
		_direction = Vector2.RIGHT
	elif d < square_size.x + square_size.y:
		_offset = Vector2(half.x, -half.y + (d - square_size.x))
		_direction = Vector2.DOWN
	elif d < 2.0 * square_size.x + square_size.y:
		_offset = Vector2(half.x - (d - square_size.x - square_size.y), half.y)
		_direction = Vector2.LEFT
	else:
		_offset = Vector2(-half.x, half.y - (d - 2.0 * square_size.x - square_size.y))
		_direction = Vector2.UP


func _draw() -> void:
	var block := Rect2(_offset - Vector2(4.0, 4.0), Vector2(8.0, 8.0))
	draw_rect(block, block_color, true)
	draw_rect(block, Color(0.08, 0.09, 0.11, 1.0), false, 1.0)
	if Engine.is_editor_hint():
		var half := square_size * 0.5
		draw_rect(Rect2(-half, square_size), Color(0.4, 0.85, 1.0, 0.6), false, 1.0)
