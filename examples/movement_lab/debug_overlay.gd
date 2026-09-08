extends Node

@export var subject_path := NodePath("../Player")

@onready var hud: Control = $HudLayer/DebugHud
@onready var visualizer: Node2D = $Visualizer


func _ready() -> void:
	var subject := get_node_or_null(subject_path)
	if subject == null:
		return
	hud.call("bind_subject", subject)
	visualizer.call("bind_subject", subject)
