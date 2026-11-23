class_name MapPreciseRenderer
extends Control

## Draws the world as explored terrain cells: every room is a block of 8x8-cell
## pixels, colored only where the player has already been. Unexplored areas stay
## black so the world keeps its silhouette without leaking any content.

const SNAPSHOT: Script = preload("res://addons/metroidvania_kit/map/data/room_terrain_snapshot.gd")

const COLOR_ROOM_BACKGROUND := Color(0.016, 0.020, 0.030, 1.0)
const COLOR_UNEXPLORED_ROOM := Color(0.085, 0.10, 0.14, 1.0)
const COLOR_UNEXPLORED := Color(0.040, 0.050, 0.070, 1.0)
const COLOR_BACK := Color(0.10, 0.13, 0.19, 1.0)
const COLOR_SOLID := Color(0.42, 0.50, 0.66, 1.0)
const COLOR_ONE_WAY := Color(0.31, 0.62, 0.42, 1.0)
const COLOR_GLASS := Color(0.59, 0.82, 0.92, 1.0)
const COLOR_LADDER := Color(0.69, 0.48, 0.23, 1.0)
const COLOR_CRUMBLE := Color(0.88, 0.72, 0.23, 1.0)
const COLOR_CRUMBLE_ONE_WAY := Color(0.76, 0.62, 0.20, 1.0)
const COLOR_VISION := Color(0.24, 0.18, 0.33, 1.0)
const COLOR_BORDER := Color(0.16, 0.20, 0.27, 1.0)
const COLOR_CURRENT := Color(0.98, 0.89, 0.42, 1.0)
const COLOR_PLAYER := Color(1.0, 0.95, 0.35, 1.0)

@export var zoom := 3.0
@export var show_room_borders := true
@export var show_player := true
## Player icon size in pixels at 1x, before the progressive zoom growth.
@export var player_icon_px := 3.0

var definition: Resource
var exploration: MapExploration

var _textures: Dictionary[String, ImageTexture] = {}
var _center_cell := Vector2.ZERO
var _player_cell := Vector2i.ZERO
var _current_room_id := ""
var _fit_pending := false


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	focus_mode = Control.FOCUS_NONE


func bind(map_definition: Resource, map_exploration: MapExploration) -> void:
	set_data(map_definition, map_exploration)
	fit_all()
	queue_redraw()


## Updates the data without touching zoom or centering, so a zoomed-in map keeps
## the player's view when new cells are revealed.
func set_data(map_definition: Resource, map_exploration: MapExploration) -> void:
	definition = map_definition
	exploration = map_exploration
	_textures.clear()
	queue_redraw()


func set_player_cell(cell: Vector2i, room_id: String) -> void:
	_player_cell = cell
	_current_room_id = room_id
	queue_redraw()


func set_zoom(value: float) -> void:
	zoom = clampf(value, 1.0, 8.0)
	queue_redraw()


func set_center_cell(cell: Vector2) -> void:
	_center_cell = cell
	queue_redraw()


## Centres on every room of the world, picking the largest integer-ish zoom that
## still fits.
func fit_all() -> void:
	if definition == null:
		return
	if size.x <= 0.0 or size.y <= 0.0:
		# Not laid out yet; _draw applies the fit once the control has a size.
		_fit_pending = true
		return
	var bounds := _world_cell_bounds()
	if bounds.size == Vector2i.ZERO:
		return
	_fit_pending = false
	_center_cell = Vector2(bounds.position) + Vector2(bounds.size) * 0.5
	var fit := minf(
		size.x / maxf(float(bounds.size.x), 1.0),
		size.y / maxf(float(bounds.size.y), 1.0)
	)
	zoom = clampf(fit, 1.0, 8.0)
	queue_redraw()


func _world_cell_bounds() -> Rect2i:
	var bounds := Rect2i()
	var first := true
	for room: Resource in definition.get("rooms"):
		if room == null:
			continue
		var origin: Vector2i = MapDefinitionBuilder.room_cell_origin(room)
		var room_rect := Rect2i(origin, MapDefinitionBuilder.room_cell_size(room))
		bounds = room_rect if first else bounds.merge(room_rect)
		first = false
	return bounds


func _draw() -> void:
	if _fit_pending:
		fit_all()
	draw_rect(Rect2(Vector2.ZERO, size), COLOR_ROOM_BACKGROUND, true)
	if definition == null:
		return
	var view_center := size * 0.5
	for room: Resource in definition.get("rooms"):
		if room == null:
			continue
		var room_id := String(room.get("room_id"))
		var origin: Vector2i = MapDefinitionBuilder.room_cell_origin(room)
		var room_size: Vector2i = MapDefinitionBuilder.room_cell_size(room)
		var top_left := (Vector2(origin) - _center_cell) * zoom + view_center
		var rect := Rect2(top_left, Vector2(room_size) * zoom)
		if not rect.intersects(Rect2(Vector2.ZERO, size)):
			continue
		var texture := _room_texture(room_id, room)
		if texture != null:
			draw_texture_rect(texture, rect, false)
		if show_room_borders:
			var border := COLOR_CURRENT if room_id == _current_room_id else COLOR_BORDER
			draw_rect(rect, border, false, 1.0)
	if show_player:
		var player_point := (Vector2(_player_cell) - _center_cell) * zoom + view_center
		_draw_player_marker(player_point)


## The hero marker grows with the map only after 2x, so it stays readable when
## zoomed out and still scales with the terrain when zoomed in.
func _draw_player_marker(center: Vector2) -> void:
	var size_px := roundf(player_icon_px * maxf(1.0, zoom / 2.0))
	size_px = maxf(size_px, 3.0)
	var outline := Rect2(center - Vector2.ONE * (size_px * 0.5 + 1.0), Vector2.ONE * (size_px + 2.0))
	draw_rect(outline, Color(0.02, 0.03, 0.05, 0.9), true)
	draw_rect(Rect2(center - Vector2.ONE * (size_px * 0.5), Vector2.ONE * size_px), COLOR_PLAYER, true)


func player_marker_pixels() -> float:
	return maxf(roundf(player_icon_px * maxf(1.0, zoom / 2.0)), 3.0)


func _room_texture(room_id: String, room: Resource) -> ImageTexture:
	if _textures.has(room_id):
		return _textures[room_id]
	var image := build_room_image(room)
	if image == null:
		return null
	var texture := ImageTexture.create_from_image(image)
	_textures[room_id] = texture
	return texture


## Builds the 1 px-per-cell image for a room. Exposed for tests.
func build_room_image(room: Resource) -> Image:
	if room == null:
		return null
	var room_id := String(room.get("room_id"))
	var room_size: Vector2i = MapDefinitionBuilder.room_cell_size(room)
	if room_size.x <= 0 or room_size.y <= 0:
		return null
	var metadata: Dictionary = room.get("metadata") if room.get("metadata") != null else {}
	var terrain_path := String(metadata.get("terrain_scene_path", ""))
	var snapshot: Dictionary = SNAPSHOT.get_snapshot(terrain_path)
	var kinds: Dictionary = snapshot.get("cells", {})
	var explored: Dictionary = exploration.cells_for(room_id) if exploration != null else {}
	var image := Image.create_empty(room_size.x, room_size.y, false, Image.FORMAT_RGBA8)
	image.fill(COLOR_UNEXPLORED if not explored.is_empty() else COLOR_UNEXPLORED_ROOM)
	for cell: Vector2i in explored:
		if cell.x < 0 or cell.y < 0 or cell.x >= room_size.x or cell.y >= room_size.y:
			continue
		var kind := int(kinds.get(cell, 0))
		image.set_pixel(cell.x, cell.y, _kind_color(kind))
	return image


func _kind_color(kind: int) -> Color:
	match kind:
		SNAPSHOT.Kind.BACK:
			return COLOR_BACK
		SNAPSHOT.Kind.SOLID:
			return COLOR_SOLID
		SNAPSHOT.Kind.ONE_WAY:
			return COLOR_ONE_WAY
		SNAPSHOT.Kind.GLASS:
			return COLOR_GLASS
		SNAPSHOT.Kind.LADDER:
			return COLOR_LADDER
		SNAPSHOT.Kind.CRUMBLE:
			return COLOR_CRUMBLE
		SNAPSHOT.Kind.CRUMBLE_ONE_WAY:
			return COLOR_CRUMBLE_ONE_WAY
		SNAPSHOT.Kind.VISION:
			return COLOR_VISION
	return COLOR_UNEXPLORED
