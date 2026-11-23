@tool
class_name GasVent
extends Node2D

## A wall nozzle that keeps injecting one of the three gases.
##
## Place it on a wall with `direction` pointing into the room. The Atmosphere
## collects vents that intersect the active room and hands up to four of them to
## the GPU field, where each one adds density (and, with the incompressible
## solver, a jet) inside `radius`.

enum Channel { HEAVY, NEUTRAL, LIGHT }

const CHANNEL_COLORS: Array[Color] = [
	Color(1.0, 0.3, 0.2, 1.0),
	Color(0.2, 0.85, 1.0, 1.0),
	Color(1.0, 0.95, 0.3, 1.0),
]
const BODY_COLOR := Color(0.28, 0.3, 0.36, 1.0)
const BODY_LIGHT := Color(0.55, 0.6, 0.7, 1.0)

@export var channel: Channel = Channel.NEUTRAL:
	set(value):
		channel = value
		queue_redraw()
@export var direction := Vector2.RIGHT:
	set(value):
		direction = value.normalized() if value.length() > 0.001 else Vector2.RIGHT
		queue_redraw()
## Radius in pixels of the outlet influence.
@export_range(4.0, 64.0, 1.0) var radius := 22.0:
	set(value):
		radius = maxf(value, 4.0)
		queue_redraw()
## Density injected per second at the centre.
@export_range(0.0, 4.0, 0.05) var rate := 3.2
## Outlet velocity pushed into the room, in pixels per second.
@export_range(0.0, 1200.0, 10.0) var jet_speed := 460.0
@export var vent_id := ""


func _ready() -> void:
	add_to_group(&"gas_vent")
	if vent_id.is_empty():
		vent_id = String(name)
	queue_redraw()


## Where the gas actually enters the room (the nozzle mouth, not the node origin).
func get_outlet_position() -> Vector2:
	return global_position + direction.normalized() * radius * 0.5


func get_channel_color() -> Color:
	return CHANNEL_COLORS[clampi(int(channel), 0, CHANNEL_COLORS.size() - 1)]


func to_light_data() -> Dictionary:
	return {
		"position": get_outlet_position(),
		"direction": direction.normalized(),
		"radius": radius,
		"rate": rate,
		"jet_speed": jet_speed,
		"channel": int(channel),
	}


func _draw() -> void:
	var mouth := direction.normalized() * 4.0
	var body := Rect2(Vector2(-3.0, -5.0) - mouth * 0.5, Vector2(6.0, 10.0))
	body.position += mouth
	draw_rect(body, BODY_COLOR, true)
	draw_rect(body, BODY_LIGHT, false, 1.0)
	var nozzle := get_channel_color()
	draw_rect(Rect2(body.end.x - 1.0, -3.0, 2.0, 6.0), nozzle, true)
	if Engine.is_editor_hint():
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 24, Color(nozzle, 0.35), 1.0)
		draw_line(Vector2.ZERO, direction.normalized() * radius, Color(nozzle, 0.8), 1.0)
		draw_string(
			ThemeDB.fallback_font,
			Vector2(-10.0, -radius - 3.0),
			"%s %s" % [vent_id, Channel.keys()[channel]],
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			8,
			Color(1.0, 1.0, 1.0, 0.85)
		)
