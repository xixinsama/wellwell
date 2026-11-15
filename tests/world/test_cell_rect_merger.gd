extends Node

const MERGER := preload("res://scripts/util/cell_rect_merger.gd")


func run() -> Array[String]:
	var failures: Array[String] = []
	_assert_empty(failures)
	_assert_block(failures)
	_assert_separate_runs(failures)
	_assert_concave_shape(failures)
	return failures


func _assert_empty(failures: Array[String]) -> void:
	if not MERGER.merge([]).is_empty():
		failures.append("empty cell set produced rectangles")


func _assert_block(failures: Array[String]) -> void:
	var cells: Array[Vector2i] = [
		Vector2i(0, 0), Vector2i(1, 0),
		Vector2i(0, 1), Vector2i(1, 1),
		Vector2i(0, 2), Vector2i(1, 2),
	]
	var rects: Array[Rect2i] = MERGER.merge(cells)
	if rects.size() != 1 or rects[0] != Rect2i(0, 0, 2, 3):
		failures.append("solid 2x3 block did not merge into one rectangle")
	_assert_cover(cells, rects, failures)


func _assert_separate_runs(failures: Array[String]) -> void:
	var cells: Array[Vector2i] = [
		Vector2i(0, 0), Vector2i(0, 1),
		Vector2i(3, 0), Vector2i(3, 1),
	]
	var rects: Array[Rect2i] = MERGER.merge(cells)
	if rects.size() != 2:
		failures.append("separate vertical runs did not stay separate")
	_assert_cover(cells, rects, failures)


func _assert_concave_shape(failures: Array[String]) -> void:
	var cells: Array[Vector2i] = [
		Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0),
		Vector2i(0, 1),
		Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 2),
	]
	var rects: Array[Rect2i] = MERGER.merge(cells)
	if rects.size() >= cells.size():
		failures.append("concave shape did not reduce the collision count")
	_assert_cover(cells, rects, failures)


func _assert_cover(
	expected: Array[Vector2i],
	rects: Array[Rect2i],
	failures: Array[String]
) -> void:
	var expected_lookup: Dictionary[Vector2i, bool] = {}
	for cell: Vector2i in expected:
		expected_lookup[cell] = true
	var covered: Dictionary[Vector2i, bool] = {}
	for rect: Rect2i in rects:
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				var cell := Vector2i(x, y)
				if covered.has(cell):
					failures.append("merged rectangles overlap at %s" % cell)
				covered[cell] = true
	if covered.size() != expected_lookup.size():
		failures.append("merged rectangles changed the occupied cell count")
		return
	for cell: Vector2i in expected_lookup:
		if not covered.has(cell):
			failures.append("merged rectangles lost cell %s" % cell)
