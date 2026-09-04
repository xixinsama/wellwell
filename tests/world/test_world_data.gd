extends Node

const ROOM_DATA: Script = preload("res://scripts/world/room_data.gd")


func run() -> Array[String]:
	var failures: Array[String] = []
	_assert_room_bounds_convert_between_chunks_pixels_and_cells(failures)
	_assert_room_chunk_ids_are_stable_and_sorted(failures)
	_assert_contains_chunk_uses_room_rect(failures)
	return failures


func _assert_room_bounds_convert_between_chunks_pixels_and_cells(failures: Array[String]) -> void:
	var room: Resource = ROOM_DATA.new()
	room.room_origin_chunk = Vector2i(2, 1)
	room.room_size_chunks = Vector2i(3, 2)

	if room.get_chunk_rect() != Rect2i(2, 1, 3, 2):
		failures.append("room chunk rect was wrong")
	if room.get_pixel_rect() != Rect2i(640, 180, 960, 360):
		failures.append("room pixel rect was wrong")
	if room.get_cell_rect() != Rect2i(80, 23, 120, 46):
		failures.append("room cell rect did not use ceiled chunk cell size")


func _assert_room_chunk_ids_are_stable_and_sorted(failures: Array[String]) -> void:
	var room: Resource = ROOM_DATA.new()
	room.room_origin_chunk = Vector2i(2, 1)
	room.room_size_chunks = Vector2i(2, 2)

	var chunk_ids: Array[String] = room.get_chunk_ids("world_01")

	if chunk_ids != [
		"world_01:chunk:2,1",
		"world_01:chunk:3,1",
		"world_01:chunk:2,2",
		"world_01:chunk:3,2",
	]:
		failures.append("room chunk ids were not stable")


func _assert_contains_chunk_uses_room_rect(failures: Array[String]) -> void:
	var room: Resource = ROOM_DATA.new()
	room.room_origin_chunk = Vector2i(-1, 3)
	room.room_size_chunks = Vector2i(2, 1)

	if not room.contains_chunk(Vector2i(-1, 3)):
		failures.append("room did not contain its first chunk")
	if not room.contains_chunk(Vector2i(0, 3)):
		failures.append("room did not contain its last chunk")
	if room.contains_chunk(Vector2i(1, 3)):
		failures.append("room contained a chunk outside its width")
