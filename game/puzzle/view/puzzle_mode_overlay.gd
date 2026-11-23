class_name PuzzleModeOverlay
extends Node2D

## Slider-mode frame effect: every piece gets an animated dashed outer
## rectangle; the selected piece gets a solid rectangle instead.

const DASH_LENGTH := 3.0
const DASH_GAP := 2.0
const DASH_SPEED := 12.0
const DASH_COLOR := Color(1.0, 0.94, 0.52, 0.62)
const SELECTED_COLOR := Color(1.0, 0.96, 0.66, 1.0)
const LINE_WIDTH := 1.0

var _pieces: Array[PuzzlePiece] = []
var _selected: PuzzlePiece = null
var _cell_size: int = 8
var _dash_phase: float = 0.0
var _active: bool = false


func setup(cell_size: int, pieces: Array[PuzzlePiece]) -> void:
	_cell_size = maxi(1, cell_size)
	_pieces.clear()
	_pieces.append_array(pieces)
	z_index = 15
	set_process(false)
	set_active(false)
	queue_redraw()


func set_selected(piece: PuzzlePiece) -> void:
	_selected = piece
	queue_redraw()


func set_active(active: bool) -> void:
	_active = active
	visible = active
	set_process(active)
	if not active:
		_selected = null
	queue_redraw()


func _process(delta: float) -> void:
	_dash_phase = fposmod(_dash_phase + delta * DASH_SPEED, DASH_LENGTH + DASH_GAP)
	queue_redraw()


func _draw() -> void:
	if not _active:
		return
	for piece: PuzzlePiece in _pieces:
		if piece == null or not is_instance_valid(piece) or not piece.is_visible_in_tree():
			continue
		var bounds := piece.get_bounds()
		var rect := Rect2(
			piece.position + Vector2(bounds.position) * float(_cell_size),
			Vector2(bounds.size) * float(_cell_size)
		)
		if piece == _selected:
			draw_rect(rect, SELECTED_COLOR, false, LINE_WIDTH)
		else:
			_draw_dashed_rect(rect, DASH_COLOR, LINE_WIDTH)


func _draw_dashed_rect(rect: Rect2, color: Color, width: float) -> void:
	var points: Array[Vector2] = [
		rect.position,
		Vector2(rect.end.x, rect.position.y),
		rect.end,
		Vector2(rect.position.x, rect.end.y),
	]
	var offset := _dash_phase
	for index in 4:
		var from := points[index]
		var to := points[(index + 1) % 4]
		var edge_length := from.distance_to(to)
		if edge_length <= 0.0:
			continue
		var direction := (to - from) / edge_length
		var cursor := -fposmod(offset, DASH_LENGTH + DASH_GAP)
		while cursor < edge_length:
			var start := maxf(cursor, 0.0)
			var finish := minf(cursor + DASH_LENGTH, edge_length)
			if finish > start:
				draw_line(from + direction * start, from + direction * finish, color, width)
			cursor += DASH_LENGTH + DASH_GAP
		offset = fposmod(offset + edge_length, DASH_LENGTH + DASH_GAP)
