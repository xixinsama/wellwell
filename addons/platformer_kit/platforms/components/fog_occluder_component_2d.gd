@tool
class_name FogOccluderComponent2D
extends Node2D

## Marks its host body's collision footprint as a sight blocker for the fog.
##
## The fog asks every member of `fog_occluder` for [method is_occluding] and
## [method get_world_rect]. This component answers both from the host's
## [CollisionShape2D] children, so a platform or a door hides what is behind it
## without keeping a second copy of its size. It asks the fog to rebuild only
## when the footprint crosses an 8 px cell, so a sliding platform does not
## repaint the mask on every frame.
##
## Add it as a child of a [StaticBody2D] or [AnimatableBody2D] (the parent), or
## point [member body_path] at one. The wiring is the group name plus the two
## methods: Platformer Kit never imports the Metroidvania addon.
##
## Exploration stays monotonic: an occluder stops a cell from being revealed,
## but a cell the player already saw this visit does not go dark again when the
## occluder moves back in front of it.

const OCCLUDER_GROUP := &"fog_occluder"
const FOG_GROUP := &"fog_of_war"
const CELL_PIXELS := 8

@export var enabled := true:
	set(value):
		if enabled == value:
			return
		enabled = value
		_sync_group()
		_last_cell_rect = _footprint_cell_rect()
		_request_refresh()
		queue_redraw()
## A solid door can stay see-through by clearing this instead of leaving the group.
@export var blocks_sight := true:
	set(value):
		if blocks_sight == value:
			return
		blocks_sight = value
		_request_refresh()
		queue_redraw()
## Empty means the parent node.
@export var body_path := NodePath()
## Refresh the fog when the footprint enters a new cell. Turn it off for a body
## that is moved by hand and call [method refresh] instead.
@export var refresh_on_move := true
## Pixels. A non-zero size replaces the footprint derived from the host shapes;
## the rect starts at the component's global position.
@export var size_override := Vector2.ZERO
## Pixels. Only used together with [member size_override].
@export var footprint_offset := Vector2.ZERO

var _last_cell_rect := Rect2i()
var _last_draw_rect := Rect2()


func _enter_tree() -> void:
	_sync_group()
	_last_cell_rect = _footprint_cell_rect()
	_last_draw_rect = _world_rect()


func _ready() -> void:
	_last_cell_rect = _footprint_cell_rect()
	_last_draw_rect = _world_rect()


func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint() or not refresh_on_move or not is_occluding():
		return
	refresh_if_moved()


func _process(_delta: float) -> void:
	if not Engine.is_editor_hint():
		return
	var rect := _world_rect()
	if rect == _last_draw_rect:
		return
	_last_draw_rect = rect
	queue_redraw()


## The contract the fog of war reads.
func is_occluding() -> bool:
	return enabled and blocks_sight and _world_rect().has_area()


## The contract the fog of war reads.
func get_world_rect() -> Rect2:
	return _world_rect()


func get_body() -> Node2D:
	if body_path != NodePath():
		return get_node_or_null(body_path) as Node2D
	return get_parent() as Node2D


func set_enabled(value: bool) -> void:
	enabled = value


## Used by a door: the host stays solid while the sight blocker goes away.
func set_blocking(value: bool) -> void:
	blocks_sight = value


func is_blocking() -> bool:
	return is_occluding()


## Returns true when the footprint crossed a cell and the fog was asked to rebuild.
func refresh_if_moved() -> bool:
	var next_rect := _footprint_cell_rect()
	if next_rect == _last_cell_rect:
		return false
	_last_cell_rect = next_rect
	_request_refresh()
	return true


## Forces one rebuild, for a body that moves without physics processing.
func refresh() -> void:
	_last_cell_rect = _footprint_cell_rect()
	_request_refresh()


func _world_rect() -> Rect2:
	if size_override != Vector2.ZERO:
		return Rect2(global_position + footprint_offset, size_override)
	var host := get_body()
	if host == null:
		return Rect2()
	var result := Rect2()
	var found := false
	for child: Node in host.get_children():
		var shape_node := child as CollisionShape2D
		if shape_node == null or shape_node.disabled or shape_node.shape == null:
			continue
		var local_rect := shape_node.shape.get_rect()
		if local_rect.size == Vector2.ZERO:
			continue
		var rect: Rect2 = shape_node.global_transform * local_rect
		result = rect if not found else result.merge(rect)
		found = true
	return result


func _footprint_cell_rect() -> Rect2i:
	var rect := _world_rect()
	if not rect.has_area():
		return Rect2i()
	var first := Vector2i(
		floori(rect.position.x / CELL_PIXELS),
		floori(rect.position.y / CELL_PIXELS)
	)
	var last := Vector2i(
		floori((rect.end.x - 0.001) / CELL_PIXELS),
		floori((rect.end.y - 0.001) / CELL_PIXELS)
	)
	return Rect2i(first, last - first + Vector2i.ONE)


func _sync_group() -> void:
	if enabled:
		add_to_group(OCCLUDER_GROUP)
	else:
		remove_from_group(OCCLUDER_GROUP)


func _request_refresh() -> void:
	if Engine.is_editor_hint() or not is_inside_tree():
		return
	get_tree().call_group(FOG_GROUP, "request_refresh")


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var rect := _world_rect()
	if not rect.has_area():
		return
	var local_rect := Rect2(to_local(rect.position), rect.size)
	var color := Color(0.35, 0.78, 1.0, 0.85)
	if not is_occluding():
		color = Color(0.55, 0.55, 0.6, 0.5)
	draw_rect(local_rect, Color(color, 0.08), true)
	draw_rect(local_rect, color, false, 1.0)
	draw_string(
		ThemeDB.fallback_font,
		local_rect.position + Vector2(2.0, 8.0),
		"OCC",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		8,
		Color(1.0, 1.0, 1.0, 0.75)
	)
