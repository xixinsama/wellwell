extends Control
class_name DebugHud

@export var player_path: NodePath

var player: Node
var _player_is_explicitly_bound := false

@onready var label: Label = $Label


func _ready() -> void:
	if not _player_is_explicitly_bound and player_path != NodePath():
		player = get_node_or_null(player_path)


func bind_player(new_player: Node) -> void:
	_player_is_explicitly_bound = true
	player = new_player


func _process(_delta: float) -> void:
	if not _player_is_explicitly_bound and player == null and player_path != NodePath():
		player = get_node_or_null(player_path)
	if player == null or not player.has_method("get_debug_state"):
		label.text = "No player"
		return

	var state: Dictionary = player.call("get_debug_state")
	var velocity_value: Vector2 = state.get("velocity", Vector2.ZERO)
	var on_floor: bool = state.get("on_floor", false)
	var jump_buffer: float = state.get("jump_buffer_remaining", 0.0)
	var coyote: float = state.get("coyote_remaining", 0.0)

	label.text = "FPS %d  TPS %d\nvel %.1f, %.1f\nfloor %s\njump buf %.0f ms\ncoyote %.0f ms" % [
		Engine.get_frames_per_second(),
		Engine.physics_ticks_per_second,
		velocity_value.x,
		velocity_value.y,
		str(on_floor),
		jump_buffer * 1000.0,
		coyote * 1000.0,
	]
