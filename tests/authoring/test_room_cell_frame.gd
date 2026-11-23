extends Node

const FRAME_SCRIPT := preload("res://addons/world_editor/authoring/room/room_cell_frame.gd")
const ROOT_SCRIPT := preload("res://addons/world_editor/authoring/room/room_authoring_root.gd")


func run() -> Array[String]:
	var failures: Array[String] = []
	_assert_border_is_flush(failures)
	_assert_multi_block_frame_is_one_grid(failures)
	_assert_root_blocks_follow_the_world_origin(failures)
	return failures


## A 2 px stroke centred on a rectangle grown by half the width spans exactly
## 0..2 px outside the room: no gap, no extra outward offset.
func _assert_border_is_flush(failures: Array[String]) -> void:
	var rect: Rect2 = FRAME_SCRIPT.border_rect(Rect2i(0, 0, 40, 23))
	if rect.position != Vector2(-1.0, -1.0) or rect.size != Vector2(322.0, 186.0):
		failures.append("cell frame border is not flush with the room edge: %s" % str(rect))
	var odd: Rect2 = FRAME_SCRIPT.border_rect(Rect2i(0, 23, 40, 22))
	if odd.position != Vector2(-1.0, 183.0) or odd.size != Vector2(322.0, 178.0):
		failures.append("odd-row frame border is not flush with the 22-cell block: %s" % str(odd))


## One outer frame plus one line per seam, so adjacent blocks never draw two
## overlapping rectangles (which would double the seam to 4 px).
func _assert_multi_block_frame_is_one_grid(failures: Array[String]) -> void:
	if not is_equal_approx(FRAME_SCRIPT.BORDER_PIXELS, 2.0):
		failures.append("the frame line is not 2 px")
	var thickness: float = FRAME_SCRIPT.frame_seam_width()
	if not is_equal_approx(thickness, FRAME_SCRIPT.BORDER_PIXELS):
		failures.append("frame seams are not the same 2 px line: %.1f" % thickness)
	var even_blocks: Array[Rect2i] = [
		Rect2i(0, 0, 40, 23), Rect2i(40, 0, 40, 23),
		Rect2i(0, 23, 40, 22), Rect2i(40, 23, 40, 22),
	]
	var even: Dictionary = FRAME_SCRIPT.frame_geometry(even_blocks)
	var outer: Rect2 = even["outer"]
	if outer.position != Vector2(-1.0, -1.0) or outer.size != Vector2(642.0, 362.0):
		failures.append("2x2 frame is not the union of the blocks: %s" % str(outer))
	if even["seams_x"] != [320.0]:
		failures.append("2x2 frame did not put one vertical seam at 320 px: %s" % str(even["seams_x"]))
	# Even world row: the first block row is 23 cells (184 px), the second 22 (176 px).
	if even["seams_y"] != [184.0]:
		failures.append("even-row 2x2 frame has the wrong horizontal seam: %s" % str(even["seams_y"]))

	var odd_blocks: Array[Rect2i] = [
		Rect2i(0, 0, 40, 22), Rect2i(40, 0, 40, 22),
		Rect2i(0, 22, 40, 23), Rect2i(40, 22, 40, 23),
	]
	var odd: Dictionary = FRAME_SCRIPT.frame_geometry(odd_blocks)
	if odd["seams_y"] != [176.0]:
		failures.append("odd-row 2x2 frame has the wrong horizontal seam: %s" % str(odd["seams_y"]))
	if odd["seams_x"] != [320.0]:
		failures.append("odd-row 2x2 frame changed the vertical seam: %s" % str(odd["seams_x"]))

	var single_blocks: Array[Rect2i] = [Rect2i(0, 0, 40, 23)]
	var single: Dictionary = FRAME_SCRIPT.frame_geometry(single_blocks)
	if not (single["seams_x"] as Array).is_empty() or not (single["seams_y"] as Array).is_empty():
		failures.append("a one-block room must not draw seams")


func _assert_root_blocks_follow_the_world_origin(failures: Array[String]) -> void:
	var root: Node2D = ROOT_SCRIPT.new() as Node2D
	root.set("room_size_chunks", Vector2i.ONE)
	root.set("world_origin_chunk", Vector2i(0, 0))
	root.set("world_origin_known", true)
	if root.call("get_room_block_cell_rects") != [Rect2i(0, 0, 40, 23)]:
		failures.append("even-origin room frame is not 23 cells")
	root.set("world_origin_chunk", Vector2i(0, 1))
	if root.call("get_room_block_cell_rects") != [Rect2i(0, 0, 40, 22)]:
		failures.append("odd-origin room frame is not 22 cells")
	root.set("room_size_chunks", Vector2i(2, 2))
	if root.call("get_room_block_cell_rects") != [
		Rect2i(0, 0, 40, 22), Rect2i(40, 0, 40, 22),
		Rect2i(0, 22, 40, 23), Rect2i(40, 22, 40, 23),
	]:
		failures.append("odd-origin 2x2 frames are not 22/23 alternating")
	root.free()
