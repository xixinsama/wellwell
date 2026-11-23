@tool
class_name GasBrush
extends Node2D

## Paints gas into the room's Atmosphere wherever the cursor is.
##
## The gas solver is a real velocity + pressure field, so the interesting thing to
## test is what happens *after* dye enters it: hold the left button to pour gas in,
## drag to fling it (the gas inherits the cursor's velocity, so a quick swipe leaves
## a stretched trail that the vorticity confinement then curls), right click to blow
## the room (a one-shot impulse with no dye, which shoves existing smoke without
## adding any), and 1 / 2 / 3 to switch between heavy, neutral and light gas.
##
## The gas appears at the cursor and nowhere else, which makes this the quickest way
## to see whether the simulation domain really behaves like a world: paint a puff,
## scroll the camera away and back, and the puff must still be there, in the same
## place. That is the property a camera-anchored field cannot offer (it throws away
## whatever leaves the view), so it is also how the two architectures are compared.
##
## The Atmosphere owns exactly one emitter slot; a second GasBrush, a GasInteractor
## in EMIT mode or a trail walker in the same room will fight over it (last one
## wins). Use one per room, or move to `set_gas_mover` for the others.

enum Channel { HEAVY, NEUTRAL, LIGHT }

const CHANNEL_COLORS: Array[Color] = [
	Color(1.0, 0.42, 0.24, 1.0),
	Color(0.32, 0.86, 1.0, 1.0),
	Color(1.0, 0.95, 0.42, 1.0),
]
const ATMOSPHERE_GROUP := &"atmosphere"

## Radius of the painted spot in world pixels. The simulation cell is 4 px, so
## anything under ~6 px is a single cell and the gas looks like a hard block.
@export_range(2.0, 48.0, 1.0) var radius := 13.0
## Density added per second at the centre of the brush.
@export_range(0.0, 12.0, 0.1) var rate := 6.0
## Which of the three gases the brush pours: heavy sinks, neutral drifts, light rises.
@export var channel: Channel = Channel.NEUTRAL
## How much of the cursor's own speed the emitted gas inherits. 0 makes the gas
## appear at rest and only buoyancy moves it.
@export_range(0.0, 3.0, 0.05) var follow_motion := 0.8
## Cap on the speed the cursor can fling the gas with, in px/s. The solver stores
## cells per second, so a fast swipe that is not capped can launch a plume across
## the whole room in a couple of frames.
@export_range(10.0, 400.0, 5.0) var max_fling := 140.0
## Right click: radius and velocity kick of the one-shot blow.
@export_range(4.0, 96.0, 1.0) var blow_radius := 42.0
@export_range(0.0, 400.0, 5.0) var blow_speed := 180.0

var _atmosphere: Node
var _painting := false
var _cursor := Vector2.ZERO
var _fling := Vector2.ZERO
var _painted_at := Vector2.ZERO


func _ready() -> void:
	add_to_group(&"gas_brush")
	_atmosphere = get_tree().get_first_node_in_group(ATMOSPHERE_GROUP)


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_cursor = get_global_mouse_position()
	if not _painting:
		return
	var atmosphere := _resolve_atmosphere()
	if atmosphere == null:
		return
	# The cursor can jump between two frames (or across a room transition), so the
	# derived speed is limited instead of trusted.
	var speed := ((_cursor - _painted_at) / maxf(delta, 0.001)).limit_length(max_fling)
	_fling = _fling.lerp(speed, 0.5)
	_painted_at = _cursor
	atmosphere.call("set_gas_emitter", _cursor, radius, rate, _fling * follow_motion, float(channel))


## The world position the brush is currently pointing at. Read by the diagnostic
## tool to check that screen coordinates become the world coordinates the gas
## actually lands on.
func get_cursor_world() -> Vector2:
	return _cursor


## Pours one frame of gas at a world position with an explicit initial velocity, the
## same call the input handlers make. Tests and tools drive this directly so they do
## not have to fake an OS cursor.
func paint_at(world_position: Vector2, velocity := Vector2.ZERO) -> void:
	var atmosphere := _resolve_atmosphere()
	if atmosphere == null:
		return
	_cursor = world_position
	_painted_at = world_position
	_fling = velocity.limit_length(max_fling)
	atmosphere.call("set_gas_emitter", world_position, radius, rate, velocity.limit_length(max_fling), float(channel))


## Stops pouring. Safe to call when nothing was painting.
func stop_painting() -> void:
	_painting = false
	var atmosphere := _resolve_atmosphere()
	if atmosphere != null:
		atmosphere.call("clear_gas_emitter")


## One-shot shove at a world position that moves the gas already in the room without
## adding any (`density = 0`), which is what makes it useful for testing the solver.
func blow_at(world_position: Vector2) -> void:
	var atmosphere := _resolve_atmosphere()
	if atmosphere == null:
		return
	atmosphere.call("trigger_explosion", world_position, blow_radius, blow_speed, 0.0)


func _resolve_atmosphere() -> Node:
	if _atmosphere == null or not is_instance_valid(_atmosphere):
		_atmosphere = get_tree().get_first_node_in_group(ATMOSPHERE_GROUP)
	return _atmosphere


func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		match button.button_index:
			MOUSE_BUTTON_LEFT:
				_set_painting(button.pressed)
			MOUSE_BUTTON_RIGHT:
				if button.pressed:
					_blow()
			MOUSE_BUTTON_WHEEL_UP:
				if button.pressed:
					_cycle_channel(1)
			MOUSE_BUTTON_WHEEL_DOWN:
				if button.pressed:
					_cycle_channel(-1)
	elif event is InputEventKey:
		var key := event as InputEventKey
		if not key.pressed or key.echo:
			return
		match key.keycode:
			KEY_1:
				channel = Channel.HEAVY
			KEY_2:
				channel = Channel.NEUTRAL
			KEY_3:
				channel = Channel.LIGHT
			_:
				return
		queue_redraw()


func _notification(what: int) -> void:
	# Releasing outside the window must not leave the emitter running: the field
	# would keep pouring gas at the last cursor position forever.
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT or what == NOTIFICATION_EXIT_TREE:
		_set_painting(false)


func _set_painting(painted: bool) -> void:
	if painted == _painting:
		return
	_painting = painted
	if _painting:
		_cursor = get_global_mouse_position()
		_painted_at = _cursor
		_fling = Vector2.ZERO
	else:
		stop_painting()
	queue_redraw()


func _blow() -> void:
	blow_at(get_global_mouse_position())


func _cycle_channel(step: int) -> void:
	channel = ((int(channel) + step) % 3 + 3) % 3
	queue_redraw()


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	# Editor gizmo: the brush radius, so the marker can be placed sensibly.
	var color: Color = CHANNEL_COLORS[int(channel)]
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 24, Color(color, 0.85), 1.0, true)
	draw_arc(Vector2.ZERO, blow_radius, 0.0, TAU, 32, Color(1.0, 1.0, 1.0, 0.35), 1.0, true)
	draw_string(
		ThemeDB.fallback_font,
		Vector2(radius + 3.0, 3.0),
		"gas brush %s" % ["Heavy", "Neutral", "Light"][int(channel)],
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		8,
		Color(1.0, 1.0, 1.0, 0.8)
	)
