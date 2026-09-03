extends Node
class_name TuningHotkeys

@export var player_path: NodePath
@export var step_ratio: float = 0.05

var fields: Array[StringName] = [
	&"max_speed",
	&"ground_accel",
	&"ground_decel",
	&"air_accel",
	&"air_decel",
	&"jump_speed",
	&"gravity",
	&"max_fall_speed",
	&"jump_buffer_time",
	&"coyote_time",
]
var selected_index: int = 0
var player: Node


func _ready() -> void:
	if player_path != NodePath():
		player = get_node_or_null(player_path)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key_event: InputEventKey = event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	if player == null and player_path != NodePath():
		player = get_node_or_null(player_path)
	if player == null or not "tuning" in player or player.tuning == null:
		return

	if key_event.keycode == KEY_BRACKETLEFT:
		selected_index = posmod(selected_index - 1, fields.size())
	elif key_event.keycode == KEY_BRACKETRIGHT:
		selected_index = posmod(selected_index + 1, fields.size())
	elif key_event.keycode == KEY_MINUS:
		_adjust_selected(-1.0)
	elif key_event.keycode == KEY_EQUAL:
		_adjust_selected(1.0)


func _adjust_selected(direction: float) -> void:
	var field: StringName = fields[selected_index]
	var current_value: Variant = player.tuning.get(field)
	if not (current_value is float):
		return
	var change: float = maxf(absf(current_value) * step_ratio, 0.005) * direction
	player.tuning.set(field, current_value + change)
