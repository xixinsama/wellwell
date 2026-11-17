class_name MapGridRenderer
extends Control

## Metroidvania-style map: one block per room. A room's fill brightness is its
## exploration ratio, so the world shape is always readable while unvisited
## space stays nearly black.

const CELLS_PER_CHUNK := Vector2i(40, 23)

const COLOR_BACKGROUND := Color(0.028, 0.036, 0.052, 1.0)
const COLOR_UNEXPLORED := Color(0.10, 0.125, 0.17, 1.0)
const COLOR_ROOM := Color(0.30, 0.40, 0.54, 1.0)
const COLOR_BORDER := Color(0.18, 0.22, 0.30, 1.0)
const COLOR_CURRENT := Color(0.98, 0.89, 0.42, 1.0)
const COLOR_LINK := Color(0.42, 0.50, 0.62, 1.0)
const COLOR_TEXT := Color(0.78, 0.83, 0.90, 1.0)
const COLOR_MARKER := Color(0.35, 0.85, 0.55, 1.0)

@export var zoom := 1.0
@export var block_size := Vector2(48.0, 34.0)
@export var draw_labels := true
## Player dot size in pixels at 1x, before the progressive zoom growth.
@export var player_icon_px := 3.0

var definition: Resource
var exploration: MapExploration

var _center_chunk := Vector2.ZERO
var _current_room_id := ""
var _player_cell := Vector2i.ZERO
var _font: Font = ThemeDB.fallback_font
var _fit_pending := false


func _ready() -> void:
	focus_mode = Control.FOCUS_NONE


func bind(map_definition: Resource, map_exploration: MapExploration) -> void:
	set_data(map_definition, map_exploration)
	fit_all()
	queue_redraw()


## Updates the data without touching zoom or centering.
func set_data(map_definition: Resource, map_exploration: MapExploration) -> void:
	definition = map_definition
	exploration = map_exploration
	queue_redraw()


func set_current_room(room_id: String) -> void:
	_current_room_id = room_id
	queue_redraw()


func set_player_cell(cell: Vector2i) -> void:
	_player_cell = cell
	queue_redraw()


func set_zoom(value: float) -> void:
	zoom = clampf(value, 0.5, 4.0)
	queue_redraw()


func set_center_chunk(chunk: Vector2) -> void:
	_center_chunk = chunk
	queue_redraw()


func fit_all() -> void:
	if definition == null:
		return
	if size.x <= 0.0 or size.y <= 0.0:
		_fit_pending = true
		return
	_fit_pending = false
	_center_chunk = _chunk_bounds().get_center()
	queue_redraw()


func focus_room(room_id: String) -> void:
	if definition == null:
		return
	var room: Resource = definition.call("get_room", StringName(room_id))
	if room == null:
		return
	var origin: Vector2i = Vector2i(room.get("map_position"))
	var room_size: Vector2i = Vector2i(room.get("map_size"))
	_center_chunk = Vector2(origin) + Vector2(room_size) * 0.5
	queue_redraw()


func _chunk_bounds() -> Rect2:
	var bounds := Rect2()
	var first := true
	for room: Resource in definition.get("rooms"):
		if room == null:
			continue
		var room_rect := Rect2(Vector2(room.get("map_position")), Vector2(room.get("map_size")))
		bounds = room_rect if first else bounds.merge(room_rect)
		first = false
	return bounds


func room_rect(room: Resource) -> Rect2:
	var origin := Vector2(room.get("map_position"))
	var room_size := Vector2(room.get("map_size"))
	var step := block_size * zoom
	var view_center := size * 0.5
	var position := (origin - _center_chunk) * step + view_center
	return Rect2(position, room_size * step)


func _draw() -> void:
	if _fit_pending:
		fit_all()
	draw_rect(Rect2(Vector2.ZERO, size), COLOR_BACKGROUND, true)
	if definition == null:
		return
	_draw_links()
	for room: Resource in definition.get("rooms"):
		if room == null:
			continue
		_draw_room(room)
	if _current_room_id.is_empty():
		return
	var current: Resource = definition.call("get_room", StringName(_current_room_id))
	if current == null:
		return
	var rect := room_rect(current)
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var room_size_cells: Vector2i = Vector2i(current.get("map_size")) * CELLS_PER_CHUNK
	var origin_cells: Vector2i = Vector2i(current.get("map_position")) * CELLS_PER_CHUNK
	var local := Vector2(_player_cell - origin_cells) / Vector2(room_size_cells)
	var point := rect.position + local * rect.size
	var size_px := roundf(player_icon_px * maxf(1.0, zoom / 2.0))
	size_px = maxf(size_px, 3.0)
	draw_rect(Rect2(point - Vector2.ONE * (size_px * 0.5 + 1.0), Vector2.ONE * (size_px + 2.0)), Color(0.02, 0.03, 0.05, 0.9), true)
	draw_rect(Rect2(point - Vector2.ONE * (size_px * 0.5), Vector2.ONE * size_px), COLOR_CURRENT, true)


func player_marker_pixels() -> float:
	return maxf(roundf(player_icon_px * maxf(1.0, zoom / 2.0)), 3.0)


func _draw_room(room: Resource) -> void:
	var rect := room_rect(room)
	if rect.size.x <= 0.0 or not rect.intersects(Rect2(Vector2.ZERO, size)):
		return
	var room_id := String(room.get("room_id"))
	var ratio := exploration.ratio(room_id, definition) if exploration != null else 0.0
	var fill := COLOR_UNEXPLORED.lerp(COLOR_ROOM, clampf(ratio, 0.0, 1.0))
	draw_rect(rect, fill, true)
	var border := COLOR_CURRENT if room_id == _current_room_id else COLOR_BORDER
	draw_rect(rect, border, false, 1.0 if room_id != _current_room_id else 2.0)
	if not draw_labels or rect.size.x < 26.0:
		return
	var label := "%d%%" % roundi(ratio * 100.0)
	var label_size := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 9)
	draw_string(
		_font,
		rect.position + Vector2((rect.size.x - label_size.x) * 0.5, rect.size.y - 4.0),
		label,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		9,
		COLOR_TEXT
	)
	if ratio <= 0.0:
		return
	var marker_point := rect.position + Vector2(rect.size.x - 5.0, 5.0)
	draw_rect(Rect2(marker_point - Vector2(1.5, 1.5), Vector2(3.0, 3.0)), COLOR_MARKER, true)


func _draw_links() -> void:
	for connection: Resource in definition.get("connections"):
		if connection == null:
			continue
		var from_room: Resource = definition.call("get_room", StringName(connection.get("from_room_id")))
		var to_room: Resource = definition.call("get_room", StringName(connection.get("to_room_id")))
		if from_room == null or to_room == null:
			continue
		var from_rect := room_rect(from_room)
		var to_rect := room_rect(to_room)
		var notch := _link_notch(from_rect, to_rect)
		if notch.size.x > 0.0 and notch.size.y > 0.0:
			draw_rect(notch, COLOR_LINK, true)


func _link_notch(from_rect: Rect2, to_rect: Rect2) -> Rect2:
	var thickness := 4.0 * zoom
	# Horizontal neighbours: shared vertical edge.
	if absf(from_rect.end.x - to_rect.position.x) <= 1.0 or absf(to_rect.end.x - from_rect.position.x) <= 1.0:
		var left := from_rect if from_rect.position.x < to_rect.position.x else to_rect
		var top := maxf(from_rect.position.y, to_rect.position.y)
		var bottom := minf(from_rect.end.y, to_rect.end.y)
		if bottom > top:
			return Rect2(Vector2(left.end.x - thickness * 0.5, (top + bottom) * 0.5 - thickness), Vector2(thickness, thickness * 2.0))
	# Vertical neighbours: shared horizontal edge.
	if absf(from_rect.end.y - to_rect.position.y) <= 1.0 or absf(to_rect.end.y - from_rect.position.y) <= 1.0:
		var up := from_rect if from_rect.position.y < to_rect.position.y else to_rect
		var left_edge := maxf(from_rect.position.x, to_rect.position.x)
		var right_edge := minf(from_rect.end.x, to_rect.end.x)
		if right_edge > left_edge:
			return Rect2(Vector2((left_edge + right_edge) * 0.5 - thickness, up.end.y - thickness * 0.5), Vector2(thickness * 2.0, thickness))
	return Rect2()
