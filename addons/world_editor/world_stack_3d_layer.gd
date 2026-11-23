@tool
class_name WorldStack3DLayer
extends Control

## The World editor's stacked-world view: every world is a horizontal slice in
## one 3D space, its rooms lie on the slice, PORTAL doors connect two points
## inside a slice and SHUTTLE doors connect across slices. Clicking a slice emits
## [signal world_picked] so the editor can open that world's 2D view.
##
## This node is a painter: [WorldStackCamera] owns the projection, the editor
## owns the data. [method set_stack] takes a plain dictionary (see below) so the
## layer never touches [WorldData], the editor API or the scene tree of a world,
## which keeps it headless testable.
##
## [codeblock]
## {
##   "current_world_id": String,
##   "layers": [{ "index": int, "world_id": String, "name": String,
##                "color": Color, "bounds": Rect2,
##                "rooms": [{ "id": String, "rect": Rect2 }],
##                "doors": [{ "id": String, "pos": Vector2, "kind": int }] }],
##   "links": [{ "kind": "portal"|"shuttle", "paired": bool,
##               "from_layer": int, "from_pos": Vector2,
##               "to_layer": int, "to_pos": Vector2 }],
##   "dangling_count": int
## }
## [/codeblock]
## Positions and rectangles are in chunk units (one unit = one 320x180 chunk);
## the camera turns them into pixels.
##
## Navigation mirrors the prototype: left drag orbits, middle or right drag pans
## (Shift+left also pans), the wheel zooms, and a click that does not travel
## picks a slice. A readout in the corner reports the chunk x/y under the pointer
## on the layer under it, plus that layer's index and world name.

signal world_picked(world_id: String)

const CAMERA_SCRIPT := preload("res://addons/world_editor/authoring/world/world_stack_camera.gd")

# Palette for the 3D stack view.
const BACKGROUND_CENTER := Color(0.051, 0.071, 0.094)  # #0d1218
const BACKGROUND_EDGE := Color(0.020, 0.027, 0.039)  # #05070a
const GRID_COLOR := Color(0.494, 0.612, 0.745, 0.07)  # #7e9cbe
const TEAL := Color(0.475, 0.949, 0.816)  # #79f2d0
const VIOLET := Color(0.663, 0.608, 1.0)  # #a99bff
const RED := Color(0.949, 0.408, 0.373)  # #f2685f
const INK := Color(0.910, 0.933, 0.965)  # #e8eef6
const DIM := Color(0.565, 0.631, 0.714)  # #90a1b6
const PLATE_FILL := Color(0.039, 0.055, 0.075, 0.72)  # #0a0e13
const GLYPH_FILL := Color(0.039, 0.051, 0.067, 0.95)  # #0a0d11
const HAIRLINE := Color(0.494, 0.612, 0.745, 0.16)  # #7e9cbe
const DIGIT_FILL := Color(0.039, 0.051, 0.067, 0.95)  # #0a0d11

# Slab look. The prototype multiplies these by a per-part global alpha, so the
# effective numbers are what is stored here.
const SLAB_TOP_FILL_ALPHA := 0.09
const SLAB_TOP_FILL_ALPHA_HOVER := 0.16
const SLAB_TOP_OUTLINE_ALPHA := 0.5
const SLAB_TOP_OUTLINE_ALPHA_CURRENT := 0.85
const SLAB_TOP_OUTLINE_ALPHA_HOVER := 0.95
const SLAB_TOP_OUTLINE_WIDTH := 1.2
const SLAB_TOP_OUTLINE_WIDTH_CURRENT := 1.8
const SLAB_TOP_OUTLINE_WIDTH_HOVER := 2.0
const SLAB_SIDE_FRONT_FILL_ALPHA := 0.15
const SLAB_SIDE_FRONT_OUTLINE_ALPHA := 0.275
const SLAB_SIDE_BACK_FILL_ALPHA := 0.026
const SLAB_SIDE_BACK_OUTLINE_ALPHA := 0.048
const ROOM_FILL_ALPHA := 0.13
const ROOM_OUTLINE_ALPHA := 0.7
## Below this many pixels per chunk a room is too small to carry its id.
const ROOM_LABEL_MIN_PIXELS_PER_UNIT := 46.0

# Motion and link look.
const HOVER_LIFT := 0.05
const DOOR_LIFT := 0.02
const ROOM_LIFT := 0.01
const ARC_STEPS := 26
const PORTAL_LIFT := 0.5
const SHUTTLE_LIFT := 1.15
const PORTAL_WIDTH := 1.4
const SHUTTLE_WIDTH := 1.8
const DASH_LENGTH := 5.0
const DASH_GAP := 5.0
const DANGLING_STUB := Vector3(0.35, -0.3, 0.5)
const CLICK_SLOP := 4.0
const ZOOM_STEP := 1.08
const LEGEND_MARGIN := 14.0

# Axis gizmo in the top-right corner of the viewport.
const GIZMO_ORIGIN_OFFSET := Vector2(-78.0, 96.0)
const GIZMO_LENGTH := 30.0
const GIZMO_PLATE := Vector2(150.0, 150.0)
const AXIS_COLORS := [Color(0.98, 0.38, 0.38), Color(0.48, 0.90, 0.52), Color(0.42, 0.66, 0.98)]
const AXIS_NAMES := ["X", "Y", "Z"]

# Legend metrics, shared by the painter and by the readout's overlap guard.
const LEGEND_FONT_SIZE := 11
const LEGEND_SWATCH_WIDTH := 22.0
const LEGEND_SWATCH_GAP := 6.0
const LEGEND_ITEM_GAP := 14.0
const LEGEND_PADDING := Vector2(12.0, 7.0)
const LEGEND_HEIGHT := 19.0

# Cursor readout: chunk x/y of the slice under the pointer plus its layer index.
const READOUT_FONT_SIZE := 11
const READOUT_PADDING := Vector2(9.0, 4.0)
const READOUT_GAP := 8.0
const READOUT_MONO_FONTS := [
	"Cascadia Mono", "Consolas", "Courier New", "DejaVu Sans Mono", "Liberation Mono",
]

const DOOR_PORTAL := 0
const DOOR_SHUTTLE := 1

enum DragMode { NONE, ORBIT, PAN }

var _camera: WorldStackCamera
var _layers: Array[Dictionary] = []
var _links: Array = []
var _index_to_world: Dictionary = {}
var _bounds_by_index: Dictionary = {}
var _max_index := -1
var _current_world_id := ""
var _dangling_count := 0
var _hover_world_id := ""
var _drag_mode := DragMode.NONE
var _press_position := Vector2.ZERO
var _cursor_position := Vector2.ZERO
var _has_cursor := false
var _fitted_once := false
var _readout_font_override: Font


func _init() -> void:
	_camera = CAMERA_SCRIPT.new() as WorldStackCamera
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_CLICK
	mouse_default_cursor_shape = Control.CURSOR_ARROW
	clip_contents = true


func _ready() -> void:
	_sync_viewport()
	if not _layers.is_empty() and _camera.fit(_layer_bounds()):
		_fitted_once = true
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_sync_viewport()
		if not _layers.is_empty() and _camera.fit(_layer_bounds()):
			_fitted_once = true
		queue_redraw()
	elif what == NOTIFICATION_MOUSE_EXIT:
		_set_hover("")


# --- Contract ----------------------------------------------------------------

## Stores the stack to draw. The first non-empty payload frames the whole stack;
## later payloads keep the user's orbit and zoom.
func set_stack(payload: Dictionary) -> void:
	_rebuild(payload)
	_sync_viewport()
	if not _layers.is_empty() and not _fitted_once and _camera.fit(_layer_bounds()):
		_fitted_once = true
	queue_redraw()


## Frames every slice, keeping the current orbit angles.
func focus_stack() -> void:
	_sync_viewport()
	if not _layers.is_empty() and _camera.fit(_layer_bounds()):
		_fitted_once = true
	queue_redraw()


## Back to the default orbit and framed again: the 3D counterpart of the flat
## canvas reset.
func reset_view() -> void:
	_camera.reset_angles()
	focus_stack()


func get_camera() -> WorldStackCamera:
	return _camera


func get_layer_count() -> int:
	return _layers.size()


## World id of the nearest slice under [param screen_position], or "" when the
## point is outside every slice. Nearest = highest layer index, i.e. the slice
## closest to the camera.
func world_at(screen_position: Vector2) -> String:
	if _layers.is_empty():
		return ""
	_sync_viewport()
	var layer_index := _camera.pick_layer(screen_position, _layer_bounds())
	if layer_index < 0:
		return ""
	return String(_index_to_world.get(layer_index, ""))


func get_current_world_id() -> String:
	return _current_world_id


func get_dangling_count() -> int:
	return _dangling_count


## Where the pointer sits in the stack: {x, y, z, layer_index, world_id, name} in
## chunk units, or {} when there is no stack. z is the layer index — the stack
## axis, not world height. The slice under the pointer wins; off the stack the
## numbers keep tracking the pointer on layer 0, the world being edited.
func get_cursor_readout() -> Dictionary:
	if _layers.is_empty():
		return {}
	_sync_viewport()
	var pointer := _readout_position()
	var layer_index := _camera.pick_layer(pointer, _layer_bounds())
	if layer_index < 0:
		layer_index = _fallback_layer_index()
	if layer_index < 0:
		return {}
	var point := _camera.unproject(pointer, layer_index)
	return {
		"x": point.x,
		"y": point.y,
		"z": layer_index,
		"layer_index": layer_index,
		"world_id": String(_index_to_world.get(layer_index, "")),
		"name": _layer_name(layer_index),
	}


# --- Payload -----------------------------------------------------------------

func _rebuild(payload: Dictionary) -> void:
	_layers.clear()
	_index_to_world.clear()
	_bounds_by_index.clear()
	_max_index = -1
	_current_world_id = String(payload.get("current_world_id", ""))
	_dangling_count = int(payload.get("dangling_count", 0))
	var raw_links: Variant = payload.get("links", [])
	if raw_links is Array:
		_links = (raw_links as Array).duplicate(true)
	else:
		_links = []
	var raw_layers: Variant = payload.get("layers", [])
	if raw_layers is Array:
		for value: Variant in raw_layers:
			if value is Dictionary:
				var layer := _normalize_layer(value as Dictionary, _layers.size())
				if not layer.is_empty():
					_layers.append(layer)
	_layers.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_index := int(left.get("index", 0))
		var right_index := int(right.get("index", 0))
		if left_index != right_index:
			return left_index < right_index
		return String(left.get("world_id", "")) < String(right.get("world_id", ""))
	)
	for layer: Dictionary in _layers:
		var index := int(layer.get("index", 0))
		_index_to_world[index] = String(layer.get("world_id", ""))
		_bounds_by_index[index] = layer.get("bounds", Rect2(-0.5, -0.5, 1.0, 1.0)) as Rect2
		_max_index = maxi(_max_index, index)
	if not _hover_world_id.is_empty() and not _index_to_world.values().has(_hover_world_id):
		_set_hover("")


func _normalize_layer(value: Dictionary, fallback_index: int) -> Dictionary:
	var world_id := String(value.get("world_id", ""))
	if world_id.is_empty():
		return {}
	var rooms: Array[Dictionary] = []
	var raw_rooms: Variant = value.get("rooms", [])
	if raw_rooms is Array:
		for room_value: Variant in raw_rooms:
			if not (room_value is Dictionary):
				continue
			var rect: Variant = (room_value as Dictionary).get("rect", null)
			if not (rect is Rect2):
				continue
			rooms.append({
				"id": String((room_value as Dictionary).get("id", "")),
				"rect": rect as Rect2,
			})
	var doors: Array[Dictionary] = []
	var raw_doors: Variant = value.get("doors", [])
	if raw_doors is Array:
		for door_value: Variant in raw_doors:
			if not (door_value is Dictionary):
				continue
			var door := door_value as Dictionary
			var door_position: Variant = door.get("pos", null)
			if not (door_position is Vector2):
				continue
			doors.append({
				"id": String(door.get("id", "")),
				"pos": door_position as Vector2,
				"kind": int(door.get("kind", DOOR_PORTAL)),
			})
	var color := _fallback_color(world_id)
	var raw_color: Variant = value.get("color", null)
	if raw_color is Color:
		color = raw_color as Color
	var display_name := String(value.get("name", ""))
	if display_name.is_empty():
		display_name = world_id
	return {
		"index": int(value.get("index", fallback_index)),
		"world_id": world_id,
		"name": display_name,
		"color": color,
		"bounds": _layer_bounds_rect(value, rooms),
		"rooms": rooms,
		"doors": doors,
	}


func _layer_bounds_rect(value: Dictionary, rooms: Array[Dictionary]) -> Rect2:
	var raw_bounds: Variant = value.get("bounds", null)
	if raw_bounds is Rect2:
		var rect := raw_bounds as Rect2
		if rect.size.x > 0.001 and rect.size.y > 0.001:
			return rect
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	for room: Dictionary in rooms:
		var room_rect := room.get("rect", Rect2()) as Rect2
		minimum = Vector2(minf(minimum.x, room_rect.position.x), minf(minimum.y, room_rect.position.y))
		maximum = Vector2(maxf(maximum.x, room_rect.end.x), maxf(maximum.y, room_rect.end.y))
	if not (is_finite(minimum.x) and is_finite(maximum.x)) or maximum.x <= minimum.x:
		return Rect2(-0.5, -0.5, 1.0, 1.0)
	return Rect2(minimum, maximum - minimum)


func _fallback_color(world_id: String) -> Color:
	var hue := float(posmod(world_id.hash(), 360)) / 360.0
	return Color.from_hsv(hue, 1.0, 0.95)


## Slab bounds indexed by layer index, which is what the camera's `fit` and
## `pick_layer` expect. Missing indices reuse the nearest earlier slice.
func _layer_bounds() -> Array[Rect2]:
	var result: Array[Rect2] = []
	if _max_index < 0:
		return result
	var current := Rect2(-0.5, -0.5, 1.0, 1.0)
	for layer: Dictionary in _layers:
		current = layer.get("bounds", current) as Rect2
		break
	for index: int in range(_max_index + 1):
		if _bounds_by_index.has(index):
			current = _bounds_by_index[index] as Rect2
		result.append(current)
	return result


func _sync_viewport() -> void:
	if _camera == null:
		return
	_camera.viewport_size = size


## Readout anchor: the pointer, or the middle of the view before it ever moved.
func _readout_position() -> Vector2:
	return _cursor_position if _has_cursor else size * 0.5


## Off the stack the readout keeps reporting on the edited world, which the
## payload places at layer 0.
func _fallback_layer_index() -> int:
	if _index_to_world.has(0):
		return 0
	if _layers.is_empty():
		return -1
	return int(_layers[0].get("index", 0))


func _layer_name(layer_index: int) -> String:
	for layer: Dictionary in _layers:
		if int(layer.get("index", 0)) == layer_index:
			var display_name := String(layer.get("name", ""))
			return display_name if not display_name.is_empty() else String(layer.get("world_id", ""))
	return ""


# --- Input -------------------------------------------------------------------

## Left drag orbits, middle/right drag (or Shift+left) pans, wheel zooms. Only a
## plain left press+release under [constant CLICK_SLOP] picks a world: no drag of
## any kind may pick.
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_mouse_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event as InputEventMouseMotion)


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	_track_cursor(event.position)
	match event.button_index:
		MOUSE_BUTTON_LEFT:
			if event.pressed:
				_begin_drag(DragMode.PAN if event.shift_pressed else DragMode.ORBIT, event.position)
			else:
				_end_drag(event.position)
			_accept_input()
		MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT:
			if event.pressed:
				_begin_drag(DragMode.PAN, event.position)
			else:
				_end_drag(event.position)
			_accept_input()
		MOUSE_BUTTON_WHEEL_UP:
			if event.pressed:
				_camera.zoom_by(ZOOM_STEP)
				_update_hover(event.position)
				queue_redraw()
				_accept_input()
		MOUSE_BUTTON_WHEEL_DOWN:
			if event.pressed:
				_camera.zoom_by(1.0 / ZOOM_STEP)
				_update_hover(event.position)
				queue_redraw()
				_accept_input()


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	_track_cursor(event.position)
	match _drag_mode:
		DragMode.ORBIT:
			_camera.orbit(event.relative)
			queue_redraw()
			_accept_input()
		DragMode.PAN:
			_camera.pan(event.relative)
			queue_redraw()
			_accept_input()
		_:
			_update_hover(event.position)


func _begin_drag(mode: int, pointer: Vector2) -> void:
	_drag_mode = mode
	_press_position = pointer
	_apply_cursor_shape()
	if is_inside_tree():
		grab_focus()


func _end_drag(pointer: Vector2) -> void:
	var mode := _drag_mode
	_drag_mode = DragMode.NONE
	if mode == DragMode.ORBIT and pointer.distance_to(_press_position) < CLICK_SLOP:
		var world_id := world_at(pointer)
		if not world_id.is_empty():
			world_picked.emit(world_id)
	_update_hover(pointer)
	_apply_cursor_shape()


func _track_cursor(pointer: Vector2) -> void:
	_cursor_position = pointer
	_has_cursor = true
	queue_redraw()


## Accepting needs a viewport; headless tests drive this node outside the tree.
func _accept_input() -> void:
	if is_inside_tree():
		accept_event()


func _update_hover(screen_position: Vector2) -> void:
	_set_hover(world_at(screen_position))


func _set_hover(world_id: String) -> void:
	if world_id != _hover_world_id:
		_hover_world_id = world_id
		queue_redraw()
	_apply_cursor_shape()


## Pointing hand over a slice, the moving cursor while a drag is in progress.
func _apply_cursor_shape() -> void:
	if _drag_mode != DragMode.NONE:
		mouse_default_cursor_shape = Control.CURSOR_DRAG
	elif not _hover_world_id.is_empty():
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	else:
		mouse_default_cursor_shape = Control.CURSOR_ARROW



# --- Drawing -----------------------------------------------------------------

func _draw() -> void:
	if size.x < 2.0 or size.y < 2.0:
		return
	_sync_viewport()
	_draw_background()
	if _layers.is_empty():
		return
	_draw_grid()
	var ordered := _layers_by_depth()
	for layer: Dictionary in ordered:
		_draw_slab(layer)
	for layer: Dictionary in ordered:
		_draw_doors(layer)
	_draw_links()
	_draw_legend()
	_draw_axis_gizmo()


func _draw_background() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BACKGROUND_EDGE, true)
	var center := Vector2(size.x * 0.5, size.y * 0.42)
	var radius := maxf(size.x, size.y) * 0.8
	var steps := 24
	for step: int in range(steps, 0, -1):
		var ratio := float(step) / float(steps)
		draw_circle(center, radius * ratio, BACKGROUND_CENTER.lerp(BACKGROUND_EDGE, ratio))


## Faint projected reference grid on the base plane, so the space reads as depth.
func _draw_grid() -> void:
	var union := _union_bounds()
	var center := union.get_center()
	var span := maxf(maxf(union.size.x, union.size.y) * 0.9, 2.4)
	var step := _grid_step(span)
	var z := -WorldStackCamera.SLAB_THICKNESS
	var first_x := floorf((center.x - span) / step) * step
	var last_x := ceilf((center.x + span) / step) * step
	var x := first_x
	while x <= last_x + 0.0001:
		draw_line(
			_camera.project(Vector3(x, center.y - span, z)),
			_camera.project(Vector3(x, center.y + span, z)),
			GRID_COLOR,
			1.0,
			true
		)
		x += step
	var first_y := floorf((center.y - span) / step) * step
	var last_y := ceilf((center.y + span) / step) * step
	var y := first_y
	while y <= last_y + 0.0001:
		draw_line(
			_camera.project(Vector3(center.x - span, y, z)),
			_camera.project(Vector3(center.x + span, y, z)),
			GRID_COLOR,
			1.0,
			true
		)
		y += step


func _grid_step(span: float) -> float:
	for candidate: float in [0.25, 0.5, 1.0, 2.0, 4.0, 8.0, 16.0, 32.0]:
		if (2.0 * span) / candidate <= 16.0:
			return candidate
	return 32.0


func _union_bounds() -> Rect2:
	var union := Rect2()
	var first := true
	for layer: Dictionary in _layers:
		var bounds := layer.get("bounds", Rect2()) as Rect2
		union = bounds if first else union.merge(bounds)
		first = false
	return union


## Far slices first, so nearer slices paint over them.
func _layers_by_depth() -> Array[Dictionary]:
	var ordered: Array[Dictionary] = []
	ordered.assign(_layers)
	ordered.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return _layer_depth(left) > _layer_depth(right)
	)
	return ordered


func _layer_depth(layer: Dictionary) -> float:
	var bounds := layer.get("bounds", Rect2()) as Rect2
	var center := bounds.get_center()
	var y1 := center.x * sin(_camera.yaw) + center.y * cos(_camera.yaw)
	return y1 * sin(_camera.pitch) - _camera.layer_z(int(layer.get("index", 0))) * cos(_camera.pitch)


func _draw_slab(layer: Dictionary) -> void:
	var index := int(layer.get("index", 0))
	var world_id := String(layer.get("world_id", ""))
	var color := layer.get("color", DIM) as Color
	var bounds := layer.get("bounds", Rect2()) as Rect2
	var hovered := world_id == _hover_world_id
	var is_current := world_id == _current_world_id
	var lift := HOVER_LIFT if hovered else 0.0
	var z := _camera.layer_z(index) + lift
	var top := _project_rect(bounds, z)
	var bottom := _project_rect(bounds, z - WorldStackCamera.SLAB_THICKNESS)
	for corner: int in range(4):
		var next := (corner + 1) % 4
		# Only the sides facing the viewer read as thickness; the rest stay faint.
		var is_front := (top[next].y + bottom[next].y) * 0.5 > (top[corner].y + top[next].y) * 0.5
		var side := PackedVector2Array([top[corner], top[next], bottom[next], bottom[corner]])
		var fill_alpha := SLAB_SIDE_FRONT_FILL_ALPHA if is_front else SLAB_SIDE_BACK_FILL_ALPHA
		var outline_alpha := SLAB_SIDE_FRONT_OUTLINE_ALPHA if is_front else SLAB_SIDE_BACK_OUTLINE_ALPHA
		_poly(side, _with_alpha(color, fill_alpha), _with_alpha(color, outline_alpha), 1.0)
	var fill_alpha := SLAB_TOP_FILL_ALPHA_HOVER if hovered else SLAB_TOP_FILL_ALPHA
	var outline_alpha := SLAB_TOP_OUTLINE_ALPHA
	if hovered:
		outline_alpha = SLAB_TOP_OUTLINE_ALPHA_HOVER
	elif is_current:
		outline_alpha = SLAB_TOP_OUTLINE_ALPHA_CURRENT
	var outline_width := SLAB_TOP_OUTLINE_WIDTH
	if hovered:
		outline_width = SLAB_TOP_OUTLINE_WIDTH_HOVER
	elif is_current:
		outline_width = SLAB_TOP_OUTLINE_WIDTH_CURRENT
	_poly(top, _with_alpha(color, fill_alpha), _with_alpha(color, outline_alpha), outline_width)
	_draw_rooms(layer, color, z)
	_draw_name_plate(layer, color, bounds, z)


func _draw_rooms(layer: Dictionary, color: Color, z: float) -> void:
	var rooms: Array = layer.get("rooms", [])
	if rooms.is_empty():
		return
	var font := ThemeDB.fallback_font
	var room_z := z + ROOM_LIFT
	for value: Variant in rooms:
		if not (value is Dictionary):
			continue
		var room := value as Dictionary
		var rect := room.get("rect", Rect2()) as Rect2
		if rect.size.x <= 0.0 or rect.size.y <= 0.0:
			continue
		var quad := _project_rect(rect, room_z)
		_poly(quad, _with_alpha(color, ROOM_FILL_ALPHA), _with_alpha(color, ROOM_OUTLINE_ALPHA), 1.0)
		var label := String(room.get("id", ""))
		if label.is_empty() or font == null:
			continue
		var center := rect.get_center()
		var pixels_per_unit := _camera.project_scale(Vector3(center.x, center.y, room_z))
		if pixels_per_unit < ROOM_LABEL_MIN_PIXELS_PER_UNIT:
			continue
		var font_size := clampi(
			roundi(9.0 + (pixels_per_unit / maxf(_camera.world_scale(), 0.001)) * 3.2), 10, 13
		)
		var text_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		var quad_bounds := _quad_bounds(quad)
		if quad_bounds.size.x < text_size.x + 8.0 or quad_bounds.size.y < float(font_size) + 6.0:
			continue
		var anchor := _camera.project(Vector3(center.x, center.y, room_z))
		_draw_text(
			anchor + Vector2(-text_size.x * 0.5, text_size.y * 0.34),
			label,
			font_size,
			_with_alpha(INK, 0.86)
		)


func _draw_name_plate(layer: Dictionary, color: Color, bounds: Rect2, z: float) -> void:
	var font := ThemeDB.fallback_font
	if font == null:
		return
	var corner := _camera.project(Vector3(bounds.position.x, bounds.position.y, z))
	var plate_y := corner.y + 16.0
	var badge_center := Vector2(corner.x + 9.0, plate_y)
	draw_circle(badge_center, 8.0, _with_alpha(color, 0.9))
	_draw_text(
		Vector2(badge_center.x, badge_center.y + 3.5),
		str(int(layer.get("index", 0)) + 1),
		10,
		DIGIT_FILL,
		true,
		true
	)
	var display_name := String(layer.get("name", ""))
	var name_size := font.get_string_size(display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
	var plate := Rect2(Vector2(corner.x + 22.0, plate_y - 9.0), Vector2(name_size.x + 14.0, 18.0))
	draw_rect(plate, PLATE_FILL, true)
	draw_rect(plate, _with_alpha(color, 0.35), false, 1.0)
	_draw_text(Vector2(corner.x + 29.0, plate_y + 4.0), display_name, 12, _with_alpha(INK, 0.95), false, true)


func _draw_doors(layer: Dictionary) -> void:
	var doors: Array = layer.get("doors", [])
	if doors.is_empty():
		return
	var index := int(layer.get("index", 0))
	var world_id := String(layer.get("world_id", ""))
	var lift := HOVER_LIFT if world_id == _hover_world_id else 0.0
	var z := _camera.layer_z(index) + DOOR_LIFT + lift
	for value: Variant in doors:
		if not (value is Dictionary):
			continue
		var door := value as Dictionary
		var door_position := door.get("pos", Vector2.ZERO) as Vector2
		var screen := _camera.project(Vector3(door_position.x, door_position.y, z))
		var pixels_per_unit := _camera.project_scale(Vector3(door_position.x, door_position.y, z))
		var radius := clampf(3.2 * pixels_per_unit / 300.0, 2.4, 6.0)
		var glyph := PackedVector2Array()
		if int(door.get("kind", DOOR_PORTAL)) == DOOR_SHUTTLE:
			glyph = PackedVector2Array([
				screen + Vector2(0.0, -radius),
				screen + Vector2(radius, 0.0),
				screen + Vector2(0.0, radius),
				screen + Vector2(-radius, 0.0),
			])
		else:
			var half := radius * 0.86
			glyph = PackedVector2Array([
				screen + Vector2(-half, -half),
				screen + Vector2(half, -half),
				screen + Vector2(half, half),
				screen + Vector2(-half, half),
			])
		var accent := VIOLET if int(door.get("kind", DOOR_PORTAL)) == DOOR_SHUTTLE else TEAL
		_poly(glyph, GLYPH_FILL, _with_alpha(accent, 1.0), 1.4)


func _draw_links() -> void:
	if _links.is_empty():
		return
	for value: Variant in _links:
		if not (value is Dictionary):
			continue
		var link := value as Dictionary
		var kind := String(link.get("kind", "portal"))
		var paired := bool(link.get("paired", false))
		var from_layer := int(link.get("from_layer", 0))
		var from_pos := link.get("from_pos", Vector2.ZERO) as Vector2
		var to_layer := int(link.get("to_layer", from_layer))
		var to_pos := link.get("to_pos", Vector2.ZERO) as Vector2
		var from_point := Vector3(from_pos.x, from_pos.y, _camera.layer_z(from_layer) + DOOR_LIFT)
		var to_point := from_point + DANGLING_STUB
		if link.has("to_pos") and _index_to_world.has(to_layer):
			to_point = Vector3(to_pos.x, to_pos.y, _camera.layer_z(to_layer) + DOOR_LIFT)
		var lift := PORTAL_LIFT if kind == "portal" else SHUTTLE_LIFT
		var width := PORTAL_WIDTH if kind == "portal" else SHUTTLE_WIDTH
		var color := TEAL if kind == "portal" else VIOLET
		if not paired:
			color = RED
		var arc := _arc_points(from_point, to_point, lift)
		if arc.size() < 2:
			continue
		if paired:
			draw_polyline(arc, color, width, true)
		else:
			_draw_dashed_polyline(arc, color, width)
		_draw_arrow_head(arc[arc.size() - 3], arc[arc.size() - 1], color, 6.0 + width * 1.6)
		if not paired:
			_draw_text(arc[arc.size() - 1] + Vector2(6.0, -6.0), "未配对", 10, _with_alpha(RED, 0.9))


## Quadratic arc in 3D, sampled and projected.
func _arc_points(from_point: Vector3, to_point: Vector3, lift: float) -> PackedVector2Array:
	var control := Vector3(
		(from_point.x + to_point.x) * 0.5,
		(from_point.y + to_point.y) * 0.5,
		(from_point.z + to_point.z) * 0.5 + lift
	)
	var points := PackedVector2Array()
	for step: int in range(ARC_STEPS + 1):
		var t := float(step) / float(ARC_STEPS)
		var inverse := 1.0 - t
		points.append(_camera.project(Vector3(
			inverse * inverse * from_point.x + 2.0 * inverse * t * control.x + t * t * to_point.x,
			inverse * inverse * from_point.y + 2.0 * inverse * t * control.y + t * t * to_point.y,
			inverse * inverse * from_point.z + 2.0 * inverse * t * control.z + t * t * to_point.z
		)))
	return points


func _draw_dashed_polyline(points: PackedVector2Array, color: Color, width: float) -> void:
	var period := DASH_LENGTH + DASH_GAP
	var travelled := 0.0
	for index: int in range(points.size() - 1):
		var start := points[index]
		var end := points[index + 1]
		var segment := start.distance_to(end)
		if segment <= 0.0001:
			continue
		var segment_start := travelled
		var segment_end := travelled + segment
		var dash_index := int(floorf(segment_start / period))
		while float(dash_index) * period < segment_end:
			var dash_start := maxf(float(dash_index) * period, segment_start)
			var dash_end := minf(float(dash_index) * period + DASH_LENGTH, segment_end)
			if dash_end > dash_start:
				draw_line(
					start.lerp(end, (dash_start - segment_start) / segment),
					start.lerp(end, (dash_end - segment_start) / segment),
					color,
					width,
					true
				)
			dash_index += 1
		travelled = segment_end


func _draw_arrow_head(from_point: Vector2, tip: Vector2, color: Color, head_size: float) -> void:
	var delta := tip - from_point
	var length := delta.length()
	if length < 0.001:
		return
	var direction := delta / length
	var normal := Vector2(-direction.y, direction.x)
	draw_colored_polygon(
		PackedVector2Array([
			tip,
			tip - direction * head_size + normal * head_size * 0.62,
			tip - direction * head_size - normal * head_size * 0.62,
		]),
		color
	)


func _legend_entries() -> Array[Dictionary]:
	return [
		{"text": "传送门（同层）", "color": TEAL, "swatch": true},
		{"text": "穿梭门（跨层）", "color": VIOLET, "swatch": true},
		{"text": "未配对", "color": RED, "swatch": true},
		{"text": "%d 层" % _layers.size(), "color": DIM, "swatch": false},
		{"text": "%d 未配对" % _dangling_count, "color": DIM, "swatch": false},
	]


func _legend_size(entries: Array[Dictionary]) -> Vector2:
	var font := ThemeDB.fallback_font
	var width := LEGEND_PADDING.x * 2.0
	for item: int in range(entries.size()):
		if item > 0:
			width += LEGEND_ITEM_GAP
		if bool(entries[item].get("swatch", false)):
			width += LEGEND_SWATCH_WIDTH + LEGEND_SWATCH_GAP
		if font != null:
			width += font.get_string_size(
				String(entries[item].get("text", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, LEGEND_FONT_SIZE
			).x
	return Vector2(width, LEGEND_HEIGHT)


func _legend_rect() -> Rect2:
	return Rect2(
		Vector2(LEGEND_MARGIN, maxf(8.0, size.y - LEGEND_HEIGHT - LEGEND_MARGIN)),
		_legend_size(_legend_entries())
	)


func _draw_legend() -> void:
	var font := ThemeDB.fallback_font
	if font == null:
		return
	var entries := _legend_entries()
	var rect := _legend_rect()
	draw_rect(rect, _with_alpha(PLATE_FILL, 0.82), true)
	draw_rect(rect, HAIRLINE, false, 1.0)
	var cursor := rect.position.x + LEGEND_PADDING.x
	var baseline := rect.position.y + LEGEND_HEIGHT * 0.5 + float(LEGEND_FONT_SIZE) * 0.36
	for item: int in range(entries.size()):
		if item > 0:
			cursor += LEGEND_ITEM_GAP
		var color := entries[item].get("color", DIM) as Color
		if bool(entries[item].get("swatch", false)):
			draw_rect(
				Rect2(
					Vector2(cursor, baseline - float(LEGEND_FONT_SIZE) * 0.42),
					Vector2(LEGEND_SWATCH_WIDTH, 2.0)
				),
				color,
				true
			)
			cursor += LEGEND_SWATCH_WIDTH + LEGEND_SWATCH_GAP
		var text := String(entries[item].get("text", ""))
		_draw_text(Vector2(cursor, baseline), text, LEGEND_FONT_SIZE, _with_alpha(color, 0.92))
		cursor += font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, LEGEND_FONT_SIZE).x


## XYZ under the pointer, bottom-right so it never sits on the legend; if the
## control is too narrow for both, it stacks just above the legend instead.
func _gizmo_plate() -> Rect2:
	var plate := Rect2(Vector2(size.x - 182.0, 56.0), GIZMO_PLATE)
	plate.position.x = clampf(plate.position.x, 4.0, maxf(4.0, size.x - plate.size.x - 4.0))
	return plate


## Axis gizmo geometry: {origin, axes: [{name, direction, tip, color}]}. The
## directions come from the live camera, so orbiting turns the axes with the view.
func get_axis_gizmo() -> Dictionary:
	var plate := _gizmo_plate()
	var origin := Vector2(plate.get_center().x, plate.position.y + 46.0)
	var axes: Array[Dictionary] = []
	if _layers.is_empty():
		return {"origin": origin, "axes": axes}
	var base := _camera.project(Vector3.ZERO)
	for axis: int in range(3):
		var unit := Vector3(
			1.0 if axis == 0 else 0.0,
			1.0 if axis == 1 else 0.0,
			1.0 if axis == 2 else 0.0
		)
		var direction := _camera.project(unit) - base
		if direction.length() < 0.001:
			continue
		direction = direction.normalized()
		axes.append({
			"name": AXIS_NAMES[axis],
			"direction": direction,
			"tip": origin + direction * GIZMO_LENGTH,
			"color": AXIS_COLORS[axis],
		})
	return {"origin": origin, "axes": axes}


## Axis gizmo plus coordinates, top-right of the viewport. The three axes are
## drawn from the live camera orientation, so orbiting turns them with the view:
## X to the right, Y down the floor plan (the chunk grid's own direction) and Z
## up the stack — the layer axis. The three axes are
## drawn from the live camera orientation, so orbiting turns them with the view:
## X to the right, Y down the floor plan (the chunk grid's own direction) and Z
## up the stack — the layer axis.
func _draw_axis_gizmo() -> void:
	var plate := _gizmo_plate()
	draw_rect(plate, _with_alpha(PLATE_FILL, 0.82), true)
	draw_rect(plate, HAIRLINE, false, 1.0)
	var gizmo := get_axis_gizmo()
	var origin: Vector2 = gizmo.get("origin", Vector2.ZERO)
	for axis: Dictionary in gizmo.get("axes", []):
		var tip: Vector2 = axis.get("tip", origin)
		var color: Color = axis.get("color", DIM)
		draw_line(origin, tip, color, 2.0, true)
		_draw_arrow_head(origin, tip, color, 9.0)
		_draw_text(
			tip + (tip - origin).normalized() * 7.0 + Vector2(-4.0, 4.0),
			String(axis.get("name", "")),
			10,
			color,
			true,
			true
		)
	var readout := get_cursor_readout()
	if readout.is_empty():
		return
	var font := _readout_font()
	if font == null:
		return
	var ascent := font.get_ascent(READOUT_FONT_SIZE)
	_draw_text_with(
		font,
		Vector2(plate.position.x + 12.0, plate.end.y - 12.0),
		_readout_text(readout),
		READOUT_FONT_SIZE,
		_with_alpha(INK, 0.92)
	)


## Compact coordinate line: the slice names already sit on the stack, so the
## gizmo only has to report x / y / z.
func _readout_text(readout: Dictionary) -> String:
	return "x %.2f   y %.2f   z %d" % [
		_clean_number(float(readout.get("x", 0.0))),
		_clean_number(float(readout.get("y", 0.0))),
		int(readout.get("layer_index", readout.get("z", 0))),
	]

## Keeps "-0.00" out of the readout when the pointer sits on a chunk boundary.
func _clean_number(value: float) -> float:
	return 0.0 if absf(value) < 0.005 else value


## Monospace keeps the digits from jittering as the pointer moves; the world name
## still reaches CJK through the OS font fallback.
func _readout_font() -> Font:
	if _readout_font_override == null:
		var mono := SystemFont.new()
		mono.font_names = PackedStringArray(READOUT_MONO_FONTS)
		mono.allow_system_fallback = true
		_readout_font_override = mono
	return _readout_font_override


# --- Small drawing helpers ---------------------------------------------------

func _project_rect(rect: Rect2, z: float) -> PackedVector2Array:
	return PackedVector2Array([
		_camera.project(Vector3(rect.position.x, rect.position.y, z)),
		_camera.project(Vector3(rect.end.x, rect.position.y, z)),
		_camera.project(Vector3(rect.end.x, rect.end.y, z)),
		_camera.project(Vector3(rect.position.x, rect.end.y, z)),
	])


func _poly(points: PackedVector2Array, fill: Color, stroke: Color, width: float) -> void:
	if points.size() < 3:
		return
	if fill.a > 0.001:
		draw_colored_polygon(points, fill)
	if stroke.a > 0.001 and width > 0.0:
		var outline := points.duplicate()
		outline.append(points[0])
		draw_polyline(outline, stroke, width, true)


func _quad_bounds(points: PackedVector2Array) -> Rect2:
	var rect := Rect2(points[0], Vector2.ZERO)
	for point: Vector2 in points:
		rect = rect.expand(point)
	return rect


func _draw_text(
	anchor: Vector2,
	text: String,
	font_size: int,
	color: Color,
	centered: bool = false,
	bold: bool = false
) -> void:
	_draw_text_with(ThemeDB.fallback_font, anchor, text, font_size, color, centered, bold)


func _draw_text_with(
	font: Font,
	anchor: Vector2,
	text: String,
	font_size: int,
	color: Color,
	centered: bool = false,
	bold: bool = false
) -> void:
	if font == null or text.is_empty():
		return
	var origin := anchor
	if centered:
		origin.x -= font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x * 0.5
	draw_string(font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
	if bold:
		draw_string(
			font, origin + Vector2(0.45, 0.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color
		)


func _with_alpha(color: Color, alpha: float) -> Color:
	return Color(color.r, color.g, color.b, alpha)
