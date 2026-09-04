class_name RoomData
extends Resource

const DEFAULT_CHUNK_SIZE_PIXELS := Vector2i(320, 180)
const DEFAULT_CELL_SIZE := Vector2i(8, 8)

@export var room_id := ""
@export var display_name := ""
@export_file("*.tscn") var scene_path := ""
@export var room_origin_chunk := Vector2i.ZERO
@export var room_size_chunks := Vector2i.ONE
@export var adjacent_room_ids: Array[String] = []
@export var map_color := Color.WHITE


static func get_chunk_size_cells(
	cell_size: Vector2i = DEFAULT_CELL_SIZE,
	chunk_size_pixels: Vector2i = DEFAULT_CHUNK_SIZE_PIXELS
) -> Vector2i:
	return Vector2i(
		_ceiling_divide(chunk_size_pixels.x, cell_size.x),
		_ceiling_divide(chunk_size_pixels.y, cell_size.y)
	)


func get_chunk_rect() -> Rect2i:
	return Rect2i(room_origin_chunk, room_size_chunks)


func get_pixel_rect(chunk_size_pixels: Vector2i = DEFAULT_CHUNK_SIZE_PIXELS) -> Rect2i:
	return Rect2i(room_origin_chunk * chunk_size_pixels, room_size_chunks * chunk_size_pixels)


func get_cell_rect(
	cell_size: Vector2i = DEFAULT_CELL_SIZE,
	chunk_size_pixels: Vector2i = DEFAULT_CHUNK_SIZE_PIXELS
) -> Rect2i:
	var chunk_size_cells := get_chunk_size_cells(cell_size, chunk_size_pixels)
	return Rect2i(room_origin_chunk * chunk_size_cells, room_size_chunks * chunk_size_cells)


func get_chunk_ids(world_id: String) -> Array[String]:
	var result: Array[String] = []
	for y: int in range(room_origin_chunk.y, room_origin_chunk.y + room_size_chunks.y):
		for x: int in range(room_origin_chunk.x, room_origin_chunk.x + room_size_chunks.x):
			result.append("%s:chunk:%d,%d" % [world_id, x, y])
	return result


func contains_chunk(chunk: Vector2i) -> bool:
	return get_chunk_rect().has_point(chunk)


static func _ceiling_divide(value: int, divisor: int) -> int:
	return int((value + divisor - 1) / divisor)
