class_name FogVisibility
extends RefCounted

## Sight spreads in eight directions. A one-cell diagonal crack is therefore
## see-through on purpose: corners are not sealed by the fog, level design keeps
## sealed spaces far enough apart so the player cannot peek through them.
const DIRECTIONS: Array[Vector2i] = [
	Vector2i.RIGHT,
	Vector2i.LEFT,
	Vector2i.DOWN,
	Vector2i.UP,
	Vector2i(1, 1),
	Vector2i(1, -1),
	Vector2i(-1, 1),
	Vector2i(-1, -1),
]


## Flood fill from the player cell, bounded by [param bounds] (inclusive cell
## coordinates). Blocker cells are visible themselves but stop propagation.
##
## [param one_way_cells] are one-way platform cells: you can see the platform
## itself, but sight does not continue downwards through it (that is what makes
## the space underneath a sealed pocket when the player stands on top).
func compute_visible_cells(
	origin: Vector2i,
	bounds: Rect2i,
	blockers: Dictionary,
	one_way_cells: Dictionary = {}
) -> Dictionary[Vector2i, bool]:
	var result: Dictionary[Vector2i, bool] = {}
	if not bounds.has_point(origin):
		return result

	var queue: Array[Vector2i] = [origin]
	result[origin] = true
	var read_index := 0

	while read_index < queue.size():
		var current := queue[read_index]
		read_index += 1
		if blockers.has(current):
			continue
		var blocks_down := one_way_cells.has(current)

		for direction: Vector2i in DIRECTIONS:
			if blocks_down and direction.y > 0:
				continue
			var next_cell := current + direction
			if result.has(next_cell):
				continue
			if not bounds.has_point(next_cell):
				continue
			result[next_cell] = true
			if not blockers.has(next_cell):
				queue.append(next_cell)

	return result


## Room-sized convenience used by older callers and tests.
func compute_room_visible_cells(
	origin: Vector2i,
	room_origin_cell: Vector2i,
	room_size_cells: Vector2i,
	blockers: Dictionary
) -> Dictionary[Vector2i, bool]:
	return compute_visible_cells(
		origin,
		Rect2i(room_origin_cell, room_size_cells),
		blockers
	)
