@tool
class_name FogDoor
extends Node2D

## A door that blocks movement and sight while closed.
##
## It fills a doorway in a room: the closed panel is a sight blocker, so the
## space behind it stays dark. Interacting with it (E / pad X) opens it, which
## removes both the collision and the fog occlusion. Door state is runtime-only;
## it resets when the room reloads.

const CELL_PIXELS := 8
const OCCLUDER_GROUP := &"fog_occluder"
const FOG_GROUP := &"fog_of_war"

@export var size_cells := Vector2i(1, 2):
	set(value):
		size_cells = Vector2i(maxi(value.x, 1), maxi(value.y, 1))
		if is_inside_tree():
			_apply_layout()
		queue_redraw()
@export var closed := true
@export var blocks_sight := true
@export var interactive := true
@export var door_id := ""

@onready var _body: StaticBody2D = $Body
@onready var _body_shape: CollisionShape2D = $Body/CollisionShape2D
@onready var _sense: Area2D = $Sense
@onready var _sense_shape: CollisionShape2D = $Sense/CollisionShape2D

var _player: Node2D


func _ready() -> void:
	add_to_group(OCCLUDER_GROUP)
	if Engine.is_editor_hint():
		return
	_apply_layout()
	_apply_state()


func is_occluding() -> bool:
	return closed and blocks_sight


func get_world_rect() -> Rect2:
	return Rect2(global_position, Vector2(size_cells) * CELL_PIXELS)


func get_body() -> StaticBody2D:
	return _body


func set_closed(value: bool) -> void:
	if closed == value:
		return
	closed = value
	_apply_state()


func toggle() -> void:
	if Engine.is_editor_hint():
		return
	set_closed(not closed)


func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint() or not interactive or not is_inside_tree():
		return
	if not Input.is_action_just_pressed("interact"):
		return
	if _sense == null or not _sense.has_overlapping_bodies():
		return
	toggle()


func _apply_layout() -> void:
	if _body_shape == null or _sense_shape == null:
		return
	var size := Vector2(size_cells) * CELL_PIXELS
	var body_rect := _body_shape.shape as RectangleShape2D
	if body_rect != null:
		body_rect.size = size
	_body_shape.position = size * 0.5
	var sense_rect := _sense_shape.shape as RectangleShape2D
	if sense_rect != null:
		sense_rect.size = size + Vector2(CELL_PIXELS, CELL_PIXELS)
	_sense_shape.position = size * 0.5


func _apply_state() -> void:
	if _body_shape != null:
		_body_shape.disabled = not closed
	if _body != null:
		_body.collision_layer = 1 if closed else 0
	queue_redraw()
	if is_inside_tree():
		get_tree().call_group(FOG_GROUP, "request_refresh")


func _draw() -> void:
	var size := Vector2(size_cells) * CELL_PIXELS
	var frame := Color(0.13, 0.1, 0.08, 1.0)
	var panel := Color(0.45, 0.31, 0.18, 1.0)
	var highlight := Color(0.7, 0.5, 0.28, 1.0)
	if closed:
		draw_rect(Rect2(Vector2.ZERO, size), panel, true)
		draw_rect(Rect2(Vector2.ZERO, size), frame, false, 1.0)
		draw_line(Vector2(1, size.y * 0.5), Vector2(size.x - 1, size.y * 0.5), highlight, 1.0)
		draw_rect(Rect2(Vector2(size.x - 4, size.y * 0.5 - 2), Vector2(2, 2)), highlight, true)
	else:
		draw_rect(Rect2(Vector2.ZERO, Vector2(size.x, 2)), frame, true)
		draw_rect(Rect2(Vector2(0, size.y - 2), Vector2(size.x, 2)), frame, true)
