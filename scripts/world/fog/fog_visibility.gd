class_name FogVisibility
extends RefCounted

const CARDINAL_DIRECTIONS: Array[Vector2i] = [
	Vector2i.RIGHT,
	Vector2i.LEFT,
	Vector2i.DOWN,
	Vector2i.UP,
]


func compute_room_visible_cells(
	origin: Vector2i,
	room_origin_cell: Vector2i,
	room_size_cells: Vector2i,
	blockers: Dictionary
) -> Dictionary[Vector2i, bool]:
	var result: Dictionary[Vector2i, bool] = {}
	if not _is_inside_room(origin, room_origin_cell, room_size_cells):
		return result

	var queue: Array[Vector2i] = [origin]
	result[origin] = true
	var read_index := 0

	while read_index < queue.size():
		var current := queue[read_index]
		read_index += 1

		if blockers.has(current):
			continue

		for direction: Vector2i in CARDINAL_DIRECTIONS:
			var next_cell := current + direction
			if result.has(next_cell):
				continue
			if not _is_inside_room(next_cell, room_origin_cell, room_size_cells):
				continue

			result[next_cell] = true
			if not blockers.has(next_cell):
				queue.append(next_cell)

	return result


func _is_inside_room(
	cell: Vector2i,
	room_origin_cell: Vector2i,
	room_size_cells: Vector2i
) -> bool:
	return (
		cell.x >= room_origin_cell.x
		and cell.y >= room_origin_cell.y
		and cell.x < room_origin_cell.x + room_size_cells.x
		and cell.y < room_origin_cell.y + room_size_cells.y
	)
