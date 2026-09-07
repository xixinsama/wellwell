class_name RoomGrid
extends RefCounted

const DEFAULT_CHUNK_SIZE_PIXELS := Vector2i(320, 180)
const DEFAULT_CELL_SIZE := Vector2i(8, 8)


static func get_cells_per_chunk(
	cell_size: Vector2i = DEFAULT_CELL_SIZE,
	chunk_size_pixels: Vector2i = DEFAULT_CHUNK_SIZE_PIXELS
) -> Vector2i:
	return Vector2i(
		_ceiling_divide(chunk_size_pixels.x, cell_size.x),
		_ceiling_divide(chunk_size_pixels.y, cell_size.y)
	)


static func get_room_cell_rect(
	origin_chunk: Vector2i,
	room_size_chunks: Vector2i,
	cell_size: Vector2i = DEFAULT_CELL_SIZE,
	chunk_size_pixels: Vector2i = DEFAULT_CHUNK_SIZE_PIXELS
) -> Rect2i:
	var cells_per_chunk := get_cells_per_chunk(cell_size, chunk_size_pixels)
	var size_pixels := room_size_chunks * chunk_size_pixels
	return Rect2i(
		origin_chunk * cells_per_chunk,
		Vector2i(
			_ceiling_divide(size_pixels.x, cell_size.x),
			_ceiling_divide(size_pixels.y, cell_size.y)
		)
	)


static func _ceiling_divide(value: int, divisor: int) -> int:
	if divisor <= 0:
		return 0
	return int((value + divisor - 1) / divisor)
