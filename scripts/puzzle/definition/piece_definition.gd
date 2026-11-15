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
## Cells that block movement from every direction. Legacy definitions that
## only fill [member shape] are treated as all-wall pieces.
@export var wall_shape: Array[Vector2i] = []
## Upward-facing one-way platform cells. They can be entered from below, left
## and right, but not from above. Kept separate from [member wall_shape] so the
## view can draw platforms above overlapping walls.
@export var one_way_shape: Array[Vector2i] = []
## Void pieces are pass-through for other sliders and are never ridable by the
## player. Their [member shape] is the void footprint.
@export var is_void: bool = false
## Whether interactive input may move this piece. Disabled pieces still occupy
## their cells and block other pieces. A disabled void piece can still be moved
## passively by an A+ induced turn.
@export var enable: bool = true
@export var initial_cell: Vector2i = Vector2i.ZERO
@export var movement_mode: MovementMode = MovementMode.FREE
## Cells travelled per horizontal input step. 1 is the classic single-cell
## slide; larger values jump straight to the destination without checking
## intermediate cells.
@export var x_move_distance: int = 1
## Cells travelled per vertical input step.
@export var y_move_distance: int = 1
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


## Cells travelled per input step along [param axis].
func get_move_distance(axis: Vector2i) -> int:
	if axis.x != 0:
		return maxi(1, x_move_distance)
	if axis.y != 0:
		return maxi(1, y_move_distance)
	return 1


## Whether interactive input may move this piece at all.
func is_controllable() -> bool:
	return enable and movement_mode != MovementMode.STATIC


## Whether this piece may slide along [param axis] (a unit Vector2i or zero).
func allows_axis(axis: Vector2i) -> bool:
	if not is_controllable():
		return false
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
