extends Control
class_name DebugHud

@export var player_path: NodePath

const VALID_SECTIONS: Array[StringName] = [&"performance", &"motor", &"sensors", &"collision", &"identity"]

var player: Node
var _player_is_explicitly_bound := false
var _sections := {
	&"performance": true,
	&"motor": true,
	&"sensors": true,
	&"collision": false,
	&"identity": true,
}

@onready var label: Label = $Label


func _ready() -> void:
	if not _player_is_explicitly_bound and player_path != NodePath():
		player = get_node_or_null(player_path)


func bind_player(new_player: Node) -> void:
	_player_is_explicitly_bound = true
	player = new_player


func bind_subject(subject: Node) -> void:
	bind_player(subject)


func set_section_enabled(section: StringName, enabled: bool) -> bool:
	if section not in VALID_SECTIONS:
		return false
	_sections[section] = enabled
	return true


func is_section_enabled(section: StringName) -> bool:
	return bool(_sections.get(section, false))


func _process(_delta: float) -> void:
	if not _player_is_explicitly_bound and player == null and player_path != NodePath():
		player = get_node_or_null(player_path)
	refresh_display()


func refresh_display() -> void:
	if label == null:
		label = get_node_or_null("Label") as Label
	if label == null:
		return
	if player == null or not player.has_method("get_debug_state"):
		label.text = "No subject"
		return

	var state: Dictionary = player.call("get_debug_state")
	var velocity_value: Vector2 = state.get("velocity", Vector2.ZERO)
	var jump_buffer: float = state.get("jump_buffer_remaining", 0.0)
	var coyote: float = state.get("coyote_remaining", 0.0)
	var lines: Array[String] = []
	if is_section_enabled(&"performance"):
		lines.append("FPS %d  TPS %d" % [Engine.get_frames_per_second(), Engine.physics_ticks_per_second])
	if is_section_enabled(&"motor"):
		lines.append("vel %.1f, %.1f" % [velocity_value.x, velocity_value.y])
		lines.append("jump buf %.0f ms  coyote %.0f ms" % [jump_buffer * 1000.0, coyote * 1000.0])
	if is_section_enabled(&"sensors"):
		lines.append("floor %s  ceiling %s" % [str(state.get("on_floor", false)), str(state.get("ceiling", false))])
		lines.append("wall L %s  R %s" % [str(state.get("wall_left", false)), str(state.get("wall_right", false))])
	if is_section_enabled(&"collision"):
		lines.append("collision shapes %d" % player.find_children("*", "CollisionShape2D", true, false).size())
	if is_section_enabled(&"identity"):
		var persistent_id := StringName()
		if player.has_method("get_persistent_id"):
			persistent_id = StringName(player.call("get_persistent_id"))
		elif "persistent_id" in player:
			persistent_id = StringName(player.get("persistent_id"))
		lines.append("id %s" % ("-" if persistent_id.is_empty() else String(persistent_id)))
	label.text = "\n".join(lines)
