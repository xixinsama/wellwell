class_name InteractionPrompt
extends Control

## Key hint for the interactable the player currently targets.
##
## It lives in the HUD, outside the game SubViewport, so the glyph is drawn at the
## window resolution instead of being scaled up with the 320x180 game frame. The
## world position of the target is converted with the SubViewport's screen
## transform, so the bubble still sits above the object on screen.
##
## The glyph follows the last input device (keyboard or gamepad) and the current
## binding from the InputMapping service, so remapping `interact` updates it.

const ACTION := &"interact"
const SLOT_KEYBOARD := 0
const SLOT_GAMEPAD := 2
## Pixels above the target origin.
const ANCHOR_LIFT := Vector2(0.0, -14.0)
const MAPPING_SERVICE := "/root/InputMapping"
const FORMATTER := preload("res://addons/input_mapping/ui/input_event_formatter.gd")

@onready var _bubble: PanelContainer = %Bubble
@onready var _glyph: Label = %Glyph

var _actor: Node2D
var _controller: Node
var _using_gamepad := false
var _glyph_text := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_resolve_actor()


func _process(_delta: float) -> void:
	_resolve_actor()
	if get_tree().paused:
		hide_prompt()
		return
	if _controller == null or not is_instance_valid(_controller):
		hide_prompt()
		return
	if not bool(_controller.call("is_available")):
		hide_prompt()
		return
	var candidate := _controller.call("get_candidate") as Node2D
	if candidate == null or not is_instance_valid(candidate) or not candidate.is_inside_tree():
		hide_prompt()
		return
	_show_for(candidate)


func _input(event: InputEvent) -> void:
	var uses_gamepad := _using_gamepad
	if event is InputEventJoypadButton:
		uses_gamepad = true
	elif event is InputEventJoypadMotion:
		if absf((event as InputEventJoypadMotion).axis_value) < 0.5:
			return
		uses_gamepad = true
	elif event is InputEventKey:
		var key_event := event as InputEventKey
		if not key_event.pressed or key_event.echo:
			return
		uses_gamepad = false
	elif event is InputEventMouseButton:
		if not (event as InputEventMouseButton).pressed:
			return
		uses_gamepad = false
	else:
		return
	if uses_gamepad == _using_gamepad:
		return
	_using_gamepad = uses_gamepad
	_sync_glyph()


## The glyph currently shown, for tests and debugging.
func get_displayed_glyph() -> String:
	return _glyph_text


## Binds the actor whose interaction controller drives the prompt. The HUD host
## calls this with the runtime player; without it the prompt falls back to the
## first `player` group member that carries an InteractionController.
func bind_actor(actor: Node2D) -> void:
	_actor = actor
	_controller = null
	if actor != null and is_instance_valid(actor):
		_controller = actor.get_node_or_null("InteractionController")
	visible = false


func hide_prompt() -> void:
	visible = false


func _show_for(candidate: Node2D) -> void:
	_sync_glyph()
	var anchor: Vector2 = candidate.get_global_transform_with_canvas().origin + ANCHOR_LIFT
	var screen_point: Vector2 = candidate.get_viewport().get_screen_transform() * anchor
	var self_to_screen := get_viewport().get_screen_transform() * get_global_transform_with_canvas()
	var local: Vector2 = self_to_screen.affine_inverse() * screen_point
	_bubble.reset_size()
	_bubble.position = (local - _bubble.size * 0.5).round()
	_place_tail(local)
	visible = true


## A small notch under the bubble that points at the object being described.
func _place_tail(anchor_local: Vector2) -> void:
	var tail := get_node_or_null("Tail") as Polygon2D
	if tail == null:
		return
	var bottom := _bubble.position.y + _bubble.size.y
	var tip_x := clampf(
		anchor_local.x,
		_bubble.position.x + 3.0,
		_bubble.position.x + _bubble.size.x - 3.0
	)
	var pocket := clampf(
		tip_x,
		_bubble.position.x + 3.5,
		_bubble.position.x + _bubble.size.x - 3.5
	)
	var tip_y := maxf(anchor_local.y - 1.0, bottom + 3.0)
	tail.polygon = PackedVector2Array([
		Vector2(pocket - 3.5, bottom - 1.0),
		Vector2(pocket + 3.5, bottom - 1.0),
		Vector2(tip_x, tip_y),
	])


func _resolve_actor() -> void:
	if _actor != null and is_instance_valid(_actor) and not _actor.is_queued_for_deletion():
		if _controller != null and is_instance_valid(_controller):
			return
	_actor = null
	_controller = null
	if not is_inside_tree():
		return
	var fallback: Node2D
	for node: Node in get_tree().get_nodes_in_group(&"player"):
		var candidate_actor := node as Node2D
		if candidate_actor == null or candidate_actor.is_queued_for_deletion():
			continue
		var candidate_controller := candidate_actor.get_node_or_null("InteractionController")
		if candidate_controller != null:
			_actor = candidate_actor
			_controller = candidate_controller
			return
		if fallback == null:
			fallback = candidate_actor
	_actor = fallback


func _sync_glyph() -> void:
	var text := _read_glyph()
	if text == _glyph_text:
		return
	_glyph_text = text
	_glyph.text = text
	_bubble.reset_size()


func _read_glyph() -> String:
	var slot := SLOT_GAMEPAD if _using_gamepad else SLOT_KEYBOARD
	var events: Array[InputEvent] = []
	var service := get_node_or_null(MAPPING_SERVICE)
	if service != null and service.has_method("get_slot_events"):
		events = service.call("get_slot_events", ACTION, slot)
	if events.is_empty():
		for event: InputEvent in InputMap.action_get_events(ACTION):
			if _event_matches_slot(event, slot):
				events.append(event)
	if events.is_empty():
		return "?"
	return _short_glyph(events[0])


func _event_matches_slot(event: InputEvent, slot: int) -> bool:
	if slot == SLOT_GAMEPAD:
		return event is InputEventJoypadButton or event is InputEventJoypadMotion
	return event is InputEventKey or event is InputEventMouseButton


func _short_glyph(event: InputEvent) -> String:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		var code := key_event.physical_keycode
		if code == KEY_NONE:
			code = key_event.keycode
		var label := OS.get_keycode_string(code)
		return label if not label.is_empty() else "?"
	if event is InputEventJoypadButton:
		match (event as InputEventJoypadButton).button_index:
			JOY_BUTTON_A:
				return "A"
			JOY_BUTTON_B:
				return "B"
			JOY_BUTTON_X:
				return "X"
			JOY_BUTTON_Y:
				return "Y"
	return FORMATTER.format_event(event)
