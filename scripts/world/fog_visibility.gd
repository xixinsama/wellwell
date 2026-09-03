class_name FogVisibility
extends RefCounted


func get_line_cells(from_cell: Vector2i, to_cell: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var x0 := from_cell.x
	var y0 := from_cell.y
	var x1 := to_cell.x
	var y1 := to_cell.y
	var dx := absi(x1 - x0)
	var sx := 1 if x0 < x1 else -1
	var dy := -absi(y1 - y0)
	var sy := 1 if y0 < y1 else -1
	var error := dx + dy

	while true:
		cells.append(Vector2i(x0, y0))
		if x0 == x1 and y0 == y1:
			break
		var twice_error := 2 * error
		if twice_error >= dy:
			error += dy
			x0 += sx
		if twice_error <= dx:
			error += dx
			y0 += sy

	return cells


func has_line_of_sight(
	from_cell: Vector2i,
	to_cell: Vector2i,
	blockers: Dictionary[Vector2i, bool]
) -> bool:
	var cells := get_line_cells(from_cell, to_cell)
	for cell: Vector2i in cells:
		if cell == from_cell or cell == to_cell:
			continue
		if blockers.has(cell):
			return false
	return true


func compute_visible_cells(
	origin: Vector2i,
	radius: int,
	blockers: Dictionary[Vector2i, bool]
) -> Dictionary[Vector2i, bool]:
	var result: Dictionary[Vector2i, bool] = {}
	var radius_squared := radius * radius
	for y: int in range(origin.y - radius, origin.y + radius + 1):
		for x: int in range(origin.x - radius, origin.x + radius + 1):
			var cell := Vector2i(x, y)
			if origin.distance_squared_to(cell) > radius_squared:
				continue
			if has_line_of_sight(origin, cell, blockers):
				result[cell] = true
	return result
