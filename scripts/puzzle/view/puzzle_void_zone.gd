class_name PuzzleVoidZone
extends Node2D

## A player-only barrier region for the puzzle board.
##
## Paint cells on the child TileMapLayer. Sliding pieces ignore this node, so
## they may move through the region; the player collides with the generated
## body only in jump mode (PlayerController removes the void layer while its
## control is locked for slider riding).

const CELL_RECT_MERGER := preload("res://scripts/util/cell_rect_merger.gd")

@export var cell_size: int = 8
## Physics layer bit used by the generated body. Layer 4 in project.godot.
@export var collision_layer: int = 1 << 3
@export var visual_layer_path: NodePath = ^"VoidTiles"

var _cells: Dictionary = {}
var _body: StaticBody2D = null


func _ready() -> void:
	refresh()


## Rebuild the cell lookup and collision body from the painted layer.
func refresh() -> void:
	var visual := get_node_or_null(visual_layer_path) as TileMapLayer
	_cells.clear()
	if visual != null:
		for cell: Vector2i in visual.get_used_cells():
			_cells[cell] = true
	_rebuild_body()


func has_cell(cell: Vector2i) -> bool:
	return _cells.has(cell)


## Whether [param world_position] falls inside a painted void cell.
func has_world_position(world_position: Vector2) -> bool:
	var local := to_local(world_position)
	var cell := Vector2i(
		floori(local.x / float(cell_size)),
		floori(local.y / float(cell_size))
	)
	return has_cell(cell)


func get_used_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	cells.assign(_cells.keys())
	cells.sort_custom(_cell_comes_before)
	return cells


func _rebuild_body() -> void:
	if _body != null and is_instance_valid(_body):
		_body.free()
		_body = null
	if _cells.is_empty():
		return
	_body = StaticBody2D.new()
	_body.name = "VoidBody"
	_body.collision_layer = collision_layer
	_body.collision_mask = 0
	add_child(_body)
	for rect: Rect2i in CELL_RECT_MERGER.merge(get_used_cells()):
		var shape := CollisionShape2D.new()
		var box := RectangleShape2D.new()
		box.size = Vector2(rect.size) * float(cell_size)
		shape.shape = box
		shape.position = (
			Vector2(rect.position) + Vector2(rect.size) * 0.5
		) * float(cell_size)
		_body.add_child(shape)


static func _cell_comes_before(a: Vector2i, b: Vector2i) -> bool:
	if a.y != b.y:
		return a.y < b.y
	return a.x < b.x
