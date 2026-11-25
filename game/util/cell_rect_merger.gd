class_name CellRectMerger
extends RefCounted

## Merges occupied grid cells into a small set of non-overlapping rectangles.
##
## The greedy pass starts at the top-left-most free cell, expands as far right
## as possible, then expands downward while every row stays full. This keeps
## vertical ladders as one rectangle and solid blocks as one rectangle while
## preserving holes and concave outlines exactly.


static func merge(cells: Array[Vector2i]) -> Array[Rect2i]:
	var remaining: Dictionary[Vector2i, bool] = {}
	for cell: Vector2i in cells:
		remaining[cell] = true
	var ordered := cells.duplicate()
	ordered.sort_custom(_cell_comes_before)

	var rects: Array[Rect2i] = []
	for cell: Vector2i in ordered:
		if not remaining.has(cell):
			continue
		var width := 0
		while remaining.has(cell + Vector2i(width, 0)):
			width += 1
		var height := 1
		while _row_is_free(remaining, cell, width, height):
			height += 1
		for y in height:
			for x in width:
				remaining.erase(cell + Vector2i(x, y))
		rects.append(Rect2i(cell, Vector2i(width, height)))
	return rects


static func _row_is_free(
	remaining: Dictionary[Vector2i, bool],
	origin: Vector2i,
	width: int,
	y: int
) -> bool:
	for x in width:
		if not remaining.has(origin + Vector2i(x, y)):
			return false
	return true


static func _cell_comes_before(a: Vector2i, b: Vector2i) -> bool:
	if a.y != b.y:
		return a.y < b.y
	return a.x < b.x
