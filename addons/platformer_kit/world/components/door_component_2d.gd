@tool
class_name DoorComponent2D
extends Node2D

## One door leaf: size, open/closed state, solid collision, interaction and the
## panel drawing.
##
## It is a component, not an entity: the author owns the body and the sense area
## and points [member body_path] / [member sense_path] at them. The closed leaf
## can hide the space behind it by listing a [FogOccluderComponent2D] in
## [member occluder_paths]; this script never talks to the fog directly, so the
## same door works in a project without the Metroidvania addon.
##
## Door state is runtime-only and resets when the room reloads.

signal door_opened()
signal door_closed()

const CELL_PIXELS := 8

@export var size_cells := Vector2i(1, 2):
	set(value):
		size_cells = Vector2i(maxi(value.x, 1), maxi(value.y, 1))
		_apply_layout()
		queue_redraw()
@export var closed := true:
	set(value):
		if closed == value:
			return
		closed = value
		_apply_state()
		queue_redraw()
## A solid door can stay see-through: the panel still blocks movement while the
## sight blocker is told to stand down.
@export var blocks_sight := true:
	set(value):
		if blocks_sight == value:
			return
		blocks_sight = value
		_apply_state()
@export var interactive := true
@export var interaction_action := &"interact"
## Collision layer the host body gets back when the door closes.
@export var solid_collision_layer := 1
## Empty means the parent node.
@export var body_path := NodePath()
@export var sense_path := NodePath()
@export var occluder_paths: Array[NodePath] = []


func _ready() -> void:
	_apply_layout()
	_apply_state()


func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint() or not interactive or not is_inside_tree():
		return
	if not InputMap.has_action(interaction_action):
		return
	if not Input.is_action_just_pressed(interaction_action):
		return
	var sense := _sense()
	if sense == null or not sense.has_overlapping_bodies():
		return
	toggle()


func is_closed() -> bool:
	return closed


func set_closed(value: bool) -> void:
	if closed == value:
		return
	closed = value
	if closed:
		door_closed.emit()
	else:
		door_opened.emit()


func toggle() -> void:
	if Engine.is_editor_hint():
		return
	set_closed(not closed)


func get_sense() -> Area2D:
	return _sense()


func _body() -> CollisionObject2D:
	if body_path != NodePath():
		return get_node_or_null(body_path) as CollisionObject2D
	return get_parent() as CollisionObject2D


func _sense() -> Area2D:
	if sense_path == NodePath():
		return null
	return get_node_or_null(sense_path) as Area2D


func _shape_node() -> CollisionShape2D:
	var host := _body()
	if host == null:
		return null
	for child: Node in host.get_children():
		var shape_node := child as CollisionShape2D
		if shape_node != null:
			return shape_node
	return null


func _apply_layout() -> void:
	var panel_size := Vector2(size_cells) * CELL_PIXELS
	var shape_node := _shape_node()
	if shape_node != null and shape_node.shape is RectangleShape2D:
		var rectangle := shape_node.shape as RectangleShape2D
		rectangle.size = panel_size
		shape_node.position = panel_size * 0.5
	var sense := _sense()
	if sense == null:
		return
	for child: Node in sense.get_children():
		var sense_shape := child as CollisionShape2D
		if sense_shape == null or not (sense_shape.shape is RectangleShape2D):
			continue
		var sense_rectangle := sense_shape.shape as RectangleShape2D
		sense_rectangle.size = panel_size + Vector2(CELL_PIXELS, CELL_PIXELS)
		sense_shape.position = panel_size * 0.5


func _apply_state() -> void:
	if Engine.is_editor_hint():
		queue_redraw()
		return
	var shape_node := _shape_node()
	if shape_node != null:
		shape_node.disabled = not closed
	var host := _body()
	if host != null:
		host.collision_layer = solid_collision_layer if closed else 0
	var blocking := closed and blocks_sight
	for path: NodePath in occluder_paths:
		var occluder := get_node_or_null(path)
		if occluder != null and occluder.has_method("set_blocking"):
			occluder.call("set_blocking", blocking)


func _draw() -> void:
	var panel_size := Vector2(size_cells) * CELL_PIXELS
	var frame := Color(0.13, 0.1, 0.08, 1.0)
	var panel := Color(0.45, 0.31, 0.18, 1.0)
	var highlight := Color(0.7, 0.5, 0.28, 1.0)
	if closed:
		draw_rect(Rect2(Vector2.ZERO, panel_size), panel, true)
		draw_rect(Rect2(Vector2.ZERO, panel_size), frame, false, 1.0)
		draw_line(
			Vector2(1, panel_size.y * 0.5),
			Vector2(panel_size.x - 1, panel_size.y * 0.5),
			highlight,
			1.0
		)
		draw_rect(
			Rect2(Vector2(panel_size.x - 4, panel_size.y * 0.5 - 2), Vector2(2, 2)),
			highlight,
			true
		)
	else:
		draw_rect(Rect2(Vector2.ZERO, Vector2(panel_size.x, 2)), frame, true)
		draw_rect(Rect2(Vector2(0, panel_size.y - 2), Vector2(panel_size.x, 2)), frame, true)
