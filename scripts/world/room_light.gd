@tool
class_name RoomLight
extends Node2D

## An authored light for `LightField`: the swinging lamp, the candelabra, the
## firefly.
##
## This is not a Godot Light2D. LightField reads these nodes and drives real
## PointLight2D nodes inside its own light viewport, so the light ends up in the
## shared light map: the darkness pass, the bloom, the water reflection, the gas
## and the fog edge all see it, and walls cast shadows from it when
## `casts_shadows` is on.
##
## Motion is authored here instead of animated in a scene so the node stays a
## single object: `swing_pixels` is a pendulum, `wander_pixels` is the drifting of
## a firefly, `flicker` is the energy wobble.

const EDITOR_PREVIEW := Color(1.0, 0.86, 0.55, 0.85)

@export var light_id := ""
@export_range(1.0, 240.0, 0.5) var radius := 48.0
@export_range(0.0, 4.0, 0.01) var energy := 1.0
@export var color := Color(1.0, 0.86, 0.62, 1.0)
## Pendulum swing around the origin, in pixels. 0 is a steady light.
@export_range(0.0, 96.0, 1.0) var swing_pixels := 0.0
@export_range(0.0, 6.0, 0.01) var swing_speed := 0.8
## Swing direction; (1, 0) is horizontal, (0, 1) vertical.
@export var swing_axis := Vector2(1.0, 0.0)
## Drift like a firefly, in pixels.
@export_range(0.0, 64.0, 1.0) var wander_pixels := 0.0
@export_range(0.0, 4.0, 0.01) var wander_speed := 0.35
## Energy wobble, as a share of `energy`.
@export_range(0.0, 1.0, 0.01) var flicker := 0.0
@export_range(0.1, 30.0, 0.1) var flicker_speed := 6.0
## Whether walls block this light. Fireflies and other "glow through walls"
## lights turn this off.
@export var casts_shadows := true


func _ready() -> void:
	add_to_group(&"room_light")
	if light_id.is_empty():
		light_id = String(name)
	queue_redraw()


## Where the light is and how bright it is at `time` seconds. The returned
## position is a world position; `energy` already includes the flicker.
func get_light_state(time: float) -> Dictionary:
	var position := global_position
	if swing_pixels > 0.0:
		var axis := swing_axis.normalized() if swing_axis.length() > 0.01 else Vector2.RIGHT
		position += axis * sin(time * swing_speed * TAU) * swing_pixels
	if wander_pixels > 0.0:
		var phase := time * wander_speed * TAU
		position += Vector2(
			sin(phase * 1.7 + position.x * 0.11),
			sin(phase * 1.13 + position.y * 0.17 + 1.7)
		) * wander_pixels
	var value := energy
	if flicker > 0.0:
		var wave := sin(time * flicker_speed + position.x * 0.37) * 0.5 + 0.5
		var wobble := sin(time * flicker_speed * 2.7 + position.y * 0.19) * 0.5 + 0.5
		value = energy * (1.0 - flicker * (1.0 - (wave * 0.7 + wobble * 0.3)))
	return {
		"position": position,
		"radius": radius,
		"energy": value,
		"color": Color(color.r, color.g, color.b, 1.0),
		"shadows": casts_shadows,
	}


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	for index: int in 4:
		var t := float(index) / 4.0
		draw_arc(Vector2.ZERO, radius * (0.25 + t * 0.75), 0.0, TAU, 20, Color(EDITOR_PREVIEW, 0.06), 1.0)
	if swing_pixels > 0.0:
		draw_line(Vector2(-swing_pixels, 0.0), Vector2(swing_pixels, 0.0), Color(EDITOR_PREVIEW, 0.4), 1.0)
	if wander_pixels > 0.0:
		draw_arc(Vector2.ZERO, wander_pixels, 0.0, TAU, 16, Color(EDITOR_PREVIEW, 0.35), 1.0)
	draw_circle(Vector2.ZERO, 1.5, EDITOR_PREVIEW)
	if not casts_shadows:
		draw_string(
			ThemeDB.fallback_font,
			Vector2(-3.0, -radius * 0.5),
			"glow",
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			7,
			Color(1.0, 1.0, 1.0, 0.6)
		)
