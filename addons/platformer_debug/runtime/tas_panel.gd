class_name TasPanel
extends PanelContainer

## HUD-space TAS status panel. It lives in the debug HUD outside the gameplay
## SubViewport so its text stays at window resolution instead of being scaled
## with the 320x180 frame.

@onready var _status: Label = %Status


func _ready() -> void:
	add_to_group("tas_panel")


func set_lines(lines: Array[String]) -> void:
	if _status == null:
		_status = get_node_or_null("%Status") as Label
	if _status != null:
		_status.text = "\n".join(lines)
