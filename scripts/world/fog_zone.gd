@tool
class_name FogZone
extends Node2D

## Authored fog composition rectangle.
##
## DARK keeps the area black until it is revealed. With reveal_on_enter the zone
## lights up the first time the player walks into it. restore_on_exit makes it
## go dark again when the player leaves (the map still keeps the explored cells).
## focus_room turns the zone into a spotlight: while the player is inside, the
## rest of the room darkens, closing in towards the player.
##
## LIGHT is always lit, even when the area is sealed off from line of sight.
## Zones are placed under RoomContent/Entities so they bake with the room.

enum Mode { DARK, LIGHT }

const CELL_PIXELS := 8

@export_enum("Dark", "Light") var mode: int = Mode.DARK:
	set(value):
		mode = value
		queue_redraw()
@export var size_cells := Vector2i(8, 4):
	set(value):
		size_cells = Vector2i(maxi(value.x, 1), maxi(value.y, 1))
		queue_redraw()
@export var zone_id := ""
@export var reveal_on_enter := true
## DARK only: re-darken the zone when the player leaves it. Exploration stays.
@export var restore_on_exit := false
## DARK only: while the player is inside, darken the rest of the room.
@export var focus_room := false
## Fade in/out time of the room spotlight. It doubles as the "the room closes in"
## beat, so it is slow enough to read as a gradient instead of a blink.
@export_range(0.05, 2.0, 0.05) var focus_seconds := 0.55
@export_range(0.0, 1.0, 0.01) var focus_alpha := 0.92

var revealed := false
var seen := false


func _ready() -> void:
	add_to_group(&"fog_zone")
	if zone_id.is_empty():
		zone_id = String(name)
	queue_redraw()


func is_light() -> bool:
	return mode == Mode.LIGHT


func get_world_rect() -> Rect2:
	return Rect2(global_position, Vector2(size_cells) * CELL_PIXELS)


func get_zone_key(room_id: String) -> String:
	return "%s:%s" % [room_id, zone_id]


func set_revealed(value: bool) -> void:
	if revealed == value:
		return
	revealed = value
	queue_redraw()


func set_seen(value: bool) -> void:
	if seen == value:
		return
	seen = value
	queue_redraw()


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var rect := Rect2(Vector2.ZERO, Vector2(size_cells) * CELL_PIXELS)
	if mode == Mode.LIGHT:
		draw_rect(rect, Color(1.0, 0.86, 0.35, 0.10), true)
		draw_rect(rect, Color(1.0, 0.86, 0.35, 0.55), false, 1.0)
	else:
		draw_rect(rect, Color(0.05, 0.03, 0.08, 0.35), true)
		var border := Color(0.62, 0.42, 0.95, 0.65)
		if restore_on_exit:
			border = Color(0.85, 0.5, 0.35, 0.8)
		if focus_room:
			border = Color(0.95, 0.75, 0.25, 0.9)
		draw_rect(rect, border, false, 1.0)
	var label := "L" if mode == Mode.LIGHT else "D"
	if restore_on_exit:
		label += "R"
	if focus_room:
		label += "F"
	if revealed or seen:
		label += "*"
	draw_string(
		ThemeDB.fallback_font,
		Vector2(2, 8),
		label,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		8,
		Color(1.0, 1.0, 1.0, 0.75)
	)
