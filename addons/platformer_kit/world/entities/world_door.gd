@tool
class_name WorldDoor
extends "res://addons/platformer_kit/world/entities/world_entity.gd"

## A paired door that moves the actor to its partner door.
##
## PORTAL pairs two doors inside one world. SHUTTLE pairs this world with
## another WorldData and swaps the whole world session for the trip. Activation
## has the same feel as a save point: contact activates the door (its colour
## changes and the state is saved) and travels at once.
##
## The arrival door stays disarmed until the actor steps out of it, so a pair can
## never bounce the actor straight back. Doors are pure data plus a drawn frame;
## there is no art dependency.

signal travel_started(kind: int, target_room_id: String, target_door_id: String)

enum Kind {
	PORTAL,
	SHUTTLE,
}

enum ActivationMode {
	CONTACT,
	INTERACT,
}

const CELL_PIXELS := 8
const DOOR_CELLS := Vector2i(2, 3)
## Physics frames without the actor inside before a disarmed door re-arms.
const REARM_FRAMES := 2

@export var door_kind := Kind.PORTAL
@export var activation_mode := ActivationMode.CONTACT
## World reached by a SHUTTLE door. Ignored by a PORTAL door.
@export var target_world: WorldData
@export var target_room_id := ""
## entity_id of the partner door; the partner points back at this door.
@export var target_door_id := ""

@export_group("Portal Colours")
@export var inactive_field_color := Color("1b2430")
@export var inactive_frame_color := Color("77879a")
@export var active_field_color := Color("0d2b28")
@export var active_frame_color := Color("79f2d0")

@export_group("Shuttle Colours")
@export var shuttle_inactive_field_color := Color("1e1a2c")
@export var shuttle_inactive_frame_color := Color("6f6690")
@export var shuttle_active_field_color := Color("1b1633")
@export var shuttle_active_frame_color := Color("a99bff")

var activated := false
var _armed := true
var _rearm_frames := 0
var _pulse := 0.0

@onready var _activation_area: Area2D = get_node_or_null("ActivationArea") as Area2D
@onready var _arrival_spawn: Node2D = get_node_or_null("ArrivalSpawn") as Node2D


func _ready() -> void:
	entity_type = "world_door"
	persistent = true
	_sync_arrival_identity()
	var interactable := get_node_or_null("Interactable") as Area2D
	if interactable != null and interactable.has_signal("interacted"):
		var callback := Callable(self, "_on_interacted")
		if not interactable.is_connected("interacted", callback):
			interactable.connect("interacted", callback)
		interactable.set("enabled", activation_mode == ActivationMode.INTERACT)
	_armed = true
	queue_redraw()


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or not activated:
		return
	_pulse += delta
	queue_redraw()


func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var occupied := _is_occupied()
	if not _armed:
		if occupied:
			_rearm_frames = 0
			return
		_rearm_frames += 1
		if _rearm_frames >= REARM_FRAMES:
			_armed = true
			_rearm_frames = 0
		return
	if not occupied or activation_mode != ActivationMode.CONTACT:
		return
	activate(null)


## True while the door accepts contact. A door is disarmed right after it sent
## or received the actor and re-arms once the actor has left it.
func is_armed() -> bool:
	return _armed


## Called on the arrival door so receiving the actor cannot trigger the return trip.
func set_arrival_disarmed() -> void:
	_armed = false
	_rearm_frames = 0


## Where the actor lands when it arrives through the partner door.
##
## The arrival point must sit outside the activation area (the scene default is
## 20px to the right, clear of the 20px-wide sensor). If it overlapped, the actor
## would be standing in the door on arrival and pair the trip back.
func get_arrival_position() -> Vector2:
	if _arrival_spawn != null:
		return _arrival_spawn.global_position
	return global_position + Vector2(DOOR_CELLS.x * CELL_PIXELS + CELL_PIXELS, 0)


func get_target_world_id() -> String:
	return "" if target_world == null else target_world.world_id


func is_link_configured() -> bool:
	return not target_room_id.is_empty() and not target_door_id.is_empty()


func activate(_actor: Node = null) -> bool:
	if Engine.is_editor_hint() or not _armed or not is_link_configured():
		return false
	_armed = false
	_rearm_frames = 0
	activated = true
	commit_save_state()
	_update_visual()
	request_save(false)
	travel_started.emit(door_kind, target_room_id, target_door_id)
	# Travel is the last thing this call does: a cross-world trip frees this very
	# room tree, so nothing below may touch the door again.
	return _travel()


func get_save_state() -> Dictionary:
	return {"activated": activated}


func apply_save_state(state: Dictionary) -> void:
	activated = bool(state.get("activated", false))
	_update_visual()


func _travel() -> bool:
	if door_kind == Kind.PORTAL:
		var runtime := _find_host(&"travel_to_door")
		if runtime == null:
			return false
		return bool(runtime.call("travel_to_door", target_room_id, target_door_id))
	var world := target_world
	if world == null or world.world_id.is_empty():
		return false
	var session := _find_host(&"travel_to_world")
	if session == null:
		return false
	return bool(session.call("travel_to_world", world, target_room_id, target_door_id))


func _find_host(method_name: StringName) -> Node:
	var node := get_parent()
	while node != null:
		if node.has_method(method_name):
			return node
		node = node.get_parent()
	return null


func _is_occupied() -> bool:
	return _activation_area != null and _activation_area.has_overlapping_bodies()


func _on_interacted(actor: Node) -> void:
	if activation_mode == ActivationMode.INTERACT:
		activate(actor)


## The arrival SpawnPoint answers to the door's entity_id, so the world runtime
## can place the actor there with the same spawn lookup it uses for every entry.
func _sync_arrival_identity() -> void:
	if _arrival_spawn == null or entity_id.is_empty():
		return
	if "spawn_id" in _arrival_spawn:
		_arrival_spawn.set("spawn_id", entity_id)


func _update_visual() -> void:
	queue_redraw()


func _frame_color() -> Color:
	if door_kind == Kind.SHUTTLE:
		return shuttle_active_frame_color if activated else shuttle_inactive_frame_color
	return active_frame_color if activated else inactive_frame_color


func _field_color() -> Color:
	if door_kind == Kind.SHUTTLE:
		return shuttle_active_field_color if activated else shuttle_inactive_field_color
	return active_field_color if activated else inactive_field_color


func _draw() -> void:
	var width := DOOR_CELLS.x * CELL_PIXELS
	var height := DOOR_CELLS.y * CELL_PIXELS
	var left := -width * 0.5
	var top := -height
	var frame := _frame_color()
	var field := _field_color()
	if activated:
		var glow := frame
		glow.a = 0.18 + 0.10 * sin(_pulse * 3.4)
		draw_rect(Rect2(left - 2, top - 2, width + 4, height + 2), glow, true)
	draw_rect(Rect2(left - 1, -2, width + 2, 2), frame.darkened(0.55), true)
	draw_rect(Rect2(left, top, width, height - 2), frame, true)
	var field_rect := Rect2(left + 2, top + 2, width - 4, height - 6)
	draw_rect(field_rect, field, true)
	if activated:
		_draw_active_glyph(field_rect, frame)
	else:
		draw_rect(field_rect, frame.darkened(0.55), false, 1.0)
		draw_rect(field_rect.grow(-3.0), frame.darkened(0.75), false, 1.0)


func _draw_active_glyph(field_rect: Rect2, frame: Color) -> void:
	if door_kind == Kind.SHUTTLE:
		_draw_shuttle_glyph(field_rect, frame)
		return
	draw_rect(field_rect.grow(-2.0), frame.darkened(0.35), false, 1.0)
	draw_rect(field_rect.grow(-5.0), frame.darkened(0.15), false, 1.0)
	var band_height := 2
	var travel := fmod(_pulse * 9.0, maxf(1.0, field_rect.size.y))
	var band_y := field_rect.position.y + field_rect.size.y - travel
	var band := Rect2(field_rect.position.x, band_y, field_rect.size.x, band_height).intersection(field_rect)
	if band.size.x > 0.0 and band.size.y > 0.0:
		var shimmer := frame
		shimmer.a = 0.45
		draw_rect(band, shimmer, true)
	var center := field_rect.get_center()
	draw_rect(Rect2(center.x - 1, center.y - 1, 2, 2), frame.lightened(0.35), true)


func _draw_shuttle_glyph(field_rect: Rect2, frame: Color) -> void:
	var center := field_rect.get_center()
	var half := 3.0
	var diamond := PackedVector2Array([
		center + Vector2(0, -half),
		center + Vector2(half, 0),
		center + Vector2(0, half),
		center + Vector2(-half, 0),
	])
	draw_colored_polygon(diamond, frame.lightened(0.1))
	draw_polyline(PackedVector2Array([diamond[0], diamond[1], diamond[2], diamond[3], diamond[0]]), frame.darkened(0.4), 1.0)
	var inset := field_rect.grow(-2.0)
	draw_rect(inset, frame.darkened(0.45), false, 1.0)
	var shift := int(round(fmod(_pulse * 3.0, 4.0)))
	draw_line(
		Vector2(inset.position.x + 2, center.y - 5 - shift),
		Vector2(inset.end.x - 2, center.y - 5 - shift),
		frame.darkened(0.1),
		1.0
	)
	draw_line(
		Vector2(inset.position.x + 2, center.y + 5 + shift),
		Vector2(inset.end.x - 2, center.y + 5 + shift),
		frame.darkened(0.1),
		1.0
	)
