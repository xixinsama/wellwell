@tool
class_name FogLight
extends Node2D

## Authored point light for the atmospheric mist.
##
## The light only affects the mist shader (it is not a Godot Light2D): the
## Atmosphere collects every emitting node and feeds the closest ones to the
## fog shader. The same falloff is available as FogGrid.sample_light() for
## tests and tooling.

const EDITOR_PREVIEW := Color(1.0, 0.82, 0.45, 0.8)

@export var light_id := ""
@export_range(8.0, 200.0, 1.0) var radius := 64.0:
	set(value):
		radius = maxf(value, 1.0)
		queue_redraw()
@export_range(0.0, 4.0, 0.05) var energy := 1.0:
	set(value):
		energy = maxf(value, 0.0)
		queue_redraw()
@export var color := Color(1.0, 0.78, 0.45, 1.0):
	set(value):
		color = value
		queue_redraw()
## Fraction of the energy that flickers; 0 is a steady light.
@export_range(0.0, 1.0, 0.01) var flicker := 0.12
@export_range(0.1, 20.0, 0.1) var flicker_speed := 5.0


func _ready() -> void:
	add_to_group(&"fog_light")
	if light_id.is_empty():
		light_id = String(name)
	queue_redraw()


## Current energy including the authored flicker. `time` is seconds.
func get_energy_at(time: float) -> float:
	if flicker <= 0.0:
		return energy
	var wave := sin(time * flicker_speed + global_position.x * 0.37) * 0.5 + 0.5
	var wobble := sin(time * flicker_speed * 2.7 + global_position.y * 0.19) * 0.5 + 0.5
	return energy * (1.0 - flicker * (1.0 - (wave * 0.7 + wobble * 0.3)))


func get_light_color() -> Color:
	return Color(color.r, color.g, color.b, 1.0)


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var steps := 20
	for index: int in steps:
		var t := float(index) / float(steps)
		var ring_radius := radius * t
		draw_arc(Vector2.ZERO, ring_radius, 0.0, TAU, 24, Color(EDITOR_PREVIEW, 0.05), 1.0)
	draw_circle(Vector2.ZERO, 2.0, EDITOR_PREVIEW)
	draw_string(
		ThemeDB.fallback_font,
		Vector2(-2.0, -radius - 2.0),
		"light %s" % light_id,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		8,
		Color(1.0, 1.0, 1.0, 0.8)
	)
