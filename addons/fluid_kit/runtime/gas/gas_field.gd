@tool
class_name GasField
extends Node2D

## Per-room gas configuration. The Atmosphere reads this marker when the room
## binds, so a room can start completely empty:
##
##   ambient = (0, 0, 0)   no background gas at all
##   decay   = 0.5         everything that is emitted fades out in ~2 seconds
##   refill  = 0           nothing is added back
##
## Put it anywhere inside the room; it is a pure data marker at runtime.

@export var ambient := Vector3(0.0, 0.0, 0.0)
@export_range(0.0, 3.0, 0.05) var decay := 0.5
@export_range(0.0, 1.0, 0.01) var diffusion := 0.25
@export_range(0.0, 2.0, 0.01) var refill := 0.0


func _ready() -> void:
	add_to_group(&"gas_field")


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	draw_rect(Rect2(-10.0, -6.0, 20.0, 12.0), Color(0.35, 0.85, 1.0, 0.25), true)
	draw_rect(Rect2(-10.0, -6.0, 20.0, 12.0), Color(0.35, 0.85, 1.0, 0.8), false, 1.0)
	draw_string(
		ThemeDB.fallback_font,
		Vector2(-9.0, -9.0),
		"gas ambient=%s decay=%.2f" % [str(ambient), decay],
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		8,
		Color(1.0, 1.0, 1.0, 0.85)
	)
