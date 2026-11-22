class_name RoomGrid
extends RefCounted

## Canonical chunk/cell conversion for rooms placed in a world.
##
## A chunk is 320x180 pixels. At 8 px cells that is 40 cells wide but 22.5 cells
## tall, so consecutive chunk rows cannot both be 23 cells. The room's cell
## rectangle is snapped to the global cell grid by rounding each block boundary:
## rows then alternate 23 / 22 cells and two rows are exactly 45 cells (360 px).
## Every room, its runtime node and the fog use this rectangle, so odd rows no
## longer drift 4 px against their neighbours.

const DEFAULT_CHUNK_SIZE_PIXELS := Vector2i(320, 180)
const DEFAULT_CELL_SIZE := Vector2i(8, 8)


## Upper bound of cells a chunk can cover. A row is 23 cells at most.
static func get_cells_per_chunk(
	cell_size: Vector2i = DEFAULT_CELL_SIZE,
	chunk_size_pixels: Vector2i = DEFAULT_CHUNK_SIZE_PIXELS
) -> Vector2i:
	return Vector2i(
		_ceiling_divide(chunk_size_pixels.x, cell_size.x),
		_ceiling_divide(chunk_size_pixels.y, cell_size.y)
	)


## The room's cell rectangle in world cells.
static func get_room_cell_rect(
	origin_chunk: Vector2i,
	room_size_chunks: Vector2i,
	cell_size: Vector2i = DEFAULT_CELL_SIZE,
	chunk_size_pixels: Vector2i = DEFAULT_CHUNK_SIZE_PIXELS
) -> Rect2i:
	var start := _cell_at_chunk(origin_chunk, cell_size, chunk_size_pixels)
	var end := _cell_at_chunk(origin_chunk + room_size_chunks, cell_size, chunk_size_pixels)
	var size := end - start
	return Rect2i(start, Vector2i(maxi(size.x, 1), maxi(size.y, 1)))


## Local cell rectangles, one per block, in room-local cells.
##
## A multi-chunk room is not one rectangle: each block row can be 23 or 22 cells
## tall depending on the world origin parity, so authors get one frame per block
## and the bake crops terrain to exactly these cells.
static func get_room_block_cell_rects(
	origin_chunk: Vector2i,
	room_size_chunks: Vector2i,
	cell_size: Vector2i = DEFAULT_CELL_SIZE,
	chunk_size_pixels: Vector2i = DEFAULT_CHUNK_SIZE_PIXELS
) -> Array[Rect2i]:
	var rects: Array[Rect2i] = []
	var base := _cell_at_chunk(origin_chunk, cell_size, chunk_size_pixels)
	for block_y: int in maxi(room_size_chunks.y, 1):
		var top := _cell_at_chunk(
			origin_chunk + Vector2i(0, block_y), cell_size, chunk_size_pixels
		).y - base.y
		var bottom := _cell_at_chunk(
			origin_chunk + Vector2i(0, block_y + 1), cell_size, chunk_size_pixels
		).y - base.y
		for block_x: int in maxi(room_size_chunks.x, 1):
			var left := _cell_at_chunk(
				origin_chunk + Vector2i(block_x, 0), cell_size, chunk_size_pixels
			).x - base.x
			var right := _cell_at_chunk(
				origin_chunk + Vector2i(block_x + 1, 0), cell_size, chunk_size_pixels
			).x - base.x
			rects.append(Rect2i(left, top, right - left, bottom - top))
	return rects


## True when [param cell] (room-local cells) belongs to one of the block frames.
static func is_local_cell_inside(
	cell: Vector2i,
	block_rects: Array[Rect2i]
) -> bool:
	for rect: Rect2i in block_rects:
		if rect.has_point(cell):
			return true
	return false


static func _cell_at_chunk(
	chunk: Vector2i,
	cell_size: Vector2i,
	chunk_size_pixels: Vector2i
) -> Vector2i:
	if cell_size.x <= 0 or cell_size.y <= 0:
		return Vector2i.ZERO
	return Vector2i(
		roundi(float(chunk.x * chunk_size_pixels.x) / float(cell_size.x)),
		roundi(float(chunk.y * chunk_size_pixels.y) / float(cell_size.y))
	)


static func _ceiling_divide(value: int, divisor: int) -> int:
	if divisor <= 0:
		return 0
	return int((value + divisor - 1) / divisor)
