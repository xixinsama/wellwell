extends Node

const PUZZLE_PIECE: Script = preload("res://scripts/puzzle/view/puzzle_piece.gd")


func run() -> Array[String]:
	var failures: Array[String] = []
	var piece: Polygon2D = PUZZLE_PIECE.new() as Polygon2D
	piece.cell_size = 8
	piece.polygon = PackedVector2Array([
		Vector2(0, 0), Vector2(16, 0), Vector2(16, 8), Vector2(0, 8)
	])
	piece.position = Vector2(96, 48)
	add_child(piece)
	if not bool(piece.call("is_occluding")):
		failures.append("a solid puzzle piece does not occlude sight")
	if not piece.is_in_group(&"fog_occluder"):
		failures.append("puzzle piece did not join the fog occluder group")
	var cells: Array[Vector2i] = piece.call("get_occluder_cells")
	if cells.size() != 2:
		failures.append("puzzle piece occluder cell count was %d" % cells.size())
	for cell: Vector2i in [Vector2i(12, 6), Vector2i(13, 6)]:
		if not cells.has(cell):
			failures.append("puzzle piece did not expose world cell %s" % cell)
	piece.position.x += 8.0
	var moved: Array[Vector2i] = piece.call("get_occluder_cells")
	for cell: Vector2i in [Vector2i(13, 6), Vector2i(14, 6)]:
		if not moved.has(cell):
			failures.append("moved puzzle piece did not expose world cell %s" % cell)
	piece.set("is_void", true)
	if bool(piece.call("is_occluding")):
		failures.append("a void puzzle piece must not occlude sight")
	piece.queue_free()
	return failures
