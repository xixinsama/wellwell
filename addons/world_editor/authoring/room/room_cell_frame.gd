@tool
class_name RoomCellFrame
extends Node2D

## Draws the room's cell frame inside the room scene itself.
##
## [RoomAuthoringRoot] creates one of these as an internal child in the editor, so
## the frame is never saved into the scene.
##
## The frame is the room's outer cell rectangle plus one line per block seam:
##
## - the outer line is 2 px thick and sits flush against the room edge — a stroke
##   centred on a rectangle grown by half the line width leaves no gap between the
##   room and its frame;
## - block seams are drawn **once each, still 2 px in total**: the line is centred
##   on the seam, so it puts 1 px into either block and never doubles into the 4 px
##   two adjacent per-block rectangles would produce;
## - a chunk row is 23 cells on even rows and 22 on odd rows (only the Y seams
##   alternate: X is always 40 cells per chunk), which is exactly where the seams
##   land.

const BORDER_PIXELS := 2.0
const CELL_PIXELS := 8.0
const SYNCED_COLOR := Color(0.35, 0.9, 0.75, 0.9)
const UNSYNCED_COLOR := Color(1.0, 0.65, 0.2, 0.9)


func _ready() -> void:
	z_index = 100
	if Engine.is_editor_hint():
		queue_redraw()


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var root := get_parent()
	if root == null or not root.has_method("get_room_block_cell_rects"):
		return
	var known: Variant = root.get("world_origin_known")
	var color := SYNCED_COLOR if known is bool and bool(known) else UNSYNCED_COLOR
	var blocks: Array[Rect2i] = []
	blocks.assign(root.call("get_room_block_cell_rects"))
	if blocks.is_empty():
		return
	var geometry := frame_geometry(blocks)
	draw_rect(geometry["outer"], color, false, BORDER_PIXELS)
	for seam: float in geometry["seams_x"]:
		draw_line(
			Vector2(seam, (geometry["outer"] as Rect2).position.y),
			Vector2(seam, (geometry["outer"] as Rect2).end.y),
			color,
			BORDER_PIXELS
		)
	for seam: float in geometry["seams_y"]:
		draw_line(
			Vector2((geometry["outer"] as Rect2).position.x, seam),
			Vector2((geometry["outer"] as Rect2).end.x, seam),
			color,
			BORDER_PIXELS
		)


## The frame in room-local pixels: one outer rectangle and the block seams.
##
## `outer` is centred on the room boundary moved out by half a line width, so the
## 2 px stroke spans `0 .. 2` px outside the room and never leaves a gap.
static func frame_geometry(
	blocks: Array[Rect2i],
	cell_pixels: float = CELL_PIXELS
) -> Dictionary:
	var union := _union_rect(blocks)
	var seam := BORDER_PIXELS * 0.5
	var outer := Rect2(
		Vector2(union.position) * cell_pixels - Vector2.ONE * seam,
		Vector2(union.size) * cell_pixels + Vector2.ONE * seam * 2.0
	)
	var seams_x: Array[float] = []
	var seams_y: Array[float] = []
	for block: Rect2i in blocks:
		var right := float(union.position.x + union.size.x)
		var bottom := float(union.position.y + union.size.y)
		var block_right := float(block.position.x + block.size.x)
		var block_bottom := float(block.position.y + block.size.y)
		if block_right < right and not seams_x.has(block_right * cell_pixels):
			seams_x.append(block_right * cell_pixels)
		if block_bottom < bottom and not seams_y.has(block_bottom * cell_pixels):
			seams_y.append(block_bottom * cell_pixels)
	seams_x.sort()
	seams_y.sort()
	return {"outer": outer, "seams_x": seams_x, "seams_y": seams_y}


## Kept for the block-legacy call sites: the flush rectangle around one block.
static func border_rect(block_cell_rect: Rect2i, cell_pixels: float = CELL_PIXELS) -> Rect2:
	var seam := BORDER_PIXELS * 0.5
	return Rect2(
		Vector2(block_cell_rect.position) * cell_pixels - Vector2.ONE * seam,
		Vector2(block_cell_rect.size) * cell_pixels + Vector2.ONE * seam * 2.0
	)


## Width of the lines drawn on block seams. One centred line, so the seam is 2 px
## in total (1 px in either block) instead of the 4 px two adjacent rectangles
## would produce.
static func frame_seam_width() -> float:
	return BORDER_PIXELS


static func _union_rect(blocks: Array[Rect2i]) -> Rect2i:
	var union := blocks[0]
	for block: Rect2i in blocks:
		union = union.merge(block)
	return union
