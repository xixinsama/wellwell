class_name PieceDefinition
extends Resource

## Static description of one sliding block ("华容道块").
##
## The puzzle core never knows names like "曹操"; it only knows the piece's
## cell shape, starting cell and which axis the piece may slide along.

enum MovementMode {
	FREE,        # Any axis-aligned direction.
	HORIZONTAL,  # Left/right only.
	VERTICAL,    # Up/down only.
	STATIC,      # Immovable obstacle.
}

@export var id: StringName = &""
## Relative cell offsets this piece occupies, measured from its anchor cell.
## Every occupied cell is listed, including the anchor itself at (0, 0).
## Free-form blocks are just non-rectangular lists of unit cells.
@export var shape: Array[Vector2i] = [Vector2i.ZERO]
@export var initial_cell: Vector2i = Vector2i.ZERO
@export var movement_mode: MovementMode = MovementMode.FREE
## Cells travelled per input step. 1 is the classic single-cell slide; larger
## values jump straight to the destination without checking intermediate cells.
@export var move_distance: int = 1
## Face colour used by the view layer's background wall.
@export var color: Color = Color(0.55, 0.55, 0.55, 1.0)


## Convenience helper for rectangular shapes.
static func make_rect_shape(size: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y in size.y:
		for x in size.x:
			cells.append(Vector2i(x, y))
	return cells


## Bounding rect (in cell coordinates) enclosing the shape, relative to the anchor.
func get_bounds() -> Rect2i:
	if shape.is_empty():
		return Rect2i(Vector2i.ZERO, Vector2i.ONE)
	var min_cell := shape[0]
	var max_cell := shape[0]
	for offset: Vector2i in shape:
		min_cell.x = mini(min_cell.x, offset.x)
		min_cell.y = mini(min_cell.y, offset.y)
		max_cell.x = maxi(max_cell.x, offset.x)
		max_cell.y = maxi(max_cell.y, offset.y)
	return Rect2i(min_cell, max_cell - min_cell + Vector2i.ONE)


## Whether this piece may slide along [param axis] (a unit Vector2i or zero).
func allows_axis(axis: Vector2i) -> bool:
	if axis == Vector2i.ZERO:
		return false
	if axis.x != 0 and axis.y != 0:
		return false
	match movement_mode:
		MovementMode.STATIC:
			return false
		MovementMode.HORIZONTAL:
			return axis.y == 0
		MovementMode.VERTICAL:
			return axis.x == 0
		_:
			return true
