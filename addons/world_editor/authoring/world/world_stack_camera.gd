class_name WorldStackCamera
extends RefCounted

## Projection for the World editor's stacked (3D) view.
##
## One world unit is one chunk (320x180 px). A layer is a horizontal slice in
## that space and its height is [constant LAYER_HEIGHT] units above the previous
## one. The camera is a tilted, slightly perspective view from above the stack:
## the yaw turns the stack, the pitch tilts it, and nearer slices project larger.
##
## Pure maths only — no nodes, no drawing, no editor API — so the view can be
## tested headless and the layer script stays a thin painter.

const LAYER_HEIGHT := 1.02
const SLAB_THICKNESS := 0.12
const FOCAL := 8.5
const MIN_ZOOM := 0.22
const MAX_ZOOM := 2.6
const PITCH_MIN := 0.42
const PITCH_MAX := 1.42
## Viewport fraction the fitted stack fills; larger than the old 0.80/0.74 so the
## slices read big instead of floating in empty space.
const FIT_WIDTH := 0.94
const FIT_HEIGHT := 0.90

var yaw := -0.46
var pitch := 1.02
var zoom := 1.0
var offset := Vector2.ZERO
var viewport_size := Vector2(800.0, 600.0)


func reset_angles() -> void:
	yaw = -0.46
	pitch = 1.02


func layer_z(layer_index: int) -> float:
	return float(layer_index) * LAYER_HEIGHT


func orbit(screen_delta: Vector2) -> void:
	yaw += screen_delta.x * 0.006
	pitch = clampf(pitch + screen_delta.y * 0.004, PITCH_MIN, PITCH_MAX)


## Moves the whole view in screen space (the stack travels with the pointer).
func pan(screen_delta: Vector2) -> void:
	offset += screen_delta


func zoom_by(factor: float) -> void:
	zoom = clampf(zoom * factor, MIN_ZOOM, MAX_ZOOM)


func world_scale() -> float:
	return minf(viewport_size.x, viewport_size.y) * 0.46 * zoom


## Projects a point in room units (x right, y down, z up) to viewport pixels.
##
## World +y points *down* the floor plan, exactly like the chunk grid and the 2D
## editor, so a room sits in the same place in both views. The stack axis is z
## and points up, like Godot's own axes.
func project(point: Vector3) -> Vector2:
	var cy := cos(yaw)
	var sy := sin(yaw)
	var py := -point.y
	var x1 := point.x * cy - py * sy
	var y1 := point.x * sy + py * cy
	var cp := cos(pitch)
	var sp := sin(pitch)
	var up := y1 * cp + point.z * sp
	var depth := y1 * sp - point.z * cp
	var k := FOCAL / maxf(1.2, FOCAL + depth)
	var scale := world_scale() * k
	return Vector2(
		viewport_size.x * 0.5 + x1 * scale + offset.x,
		viewport_size.y * 0.5 - up * scale + offset.y
	)


## Pixels per room unit at [param point]; glyphs scale with it so near slices
## stay readable and far ones shrink.
func project_scale(point: Vector3) -> float:
	var cy := cos(yaw)
	var sy := sin(yaw)
	var y1 := point.x * sy + (-point.y) * cy
	var depth := y1 * sin(pitch) - point.z * cos(pitch)
	return world_scale() * (FOCAL / maxf(1.2, FOCAL + depth))


func slab_quad(bounds: Rect2, layer_index: int) -> PackedVector2Array:
	var z := layer_z(layer_index)
	return PackedVector2Array([
		project(Vector3(bounds.position.x, bounds.position.y, z)),
		project(Vector3(bounds.end.x, bounds.position.y, z)),
		project(Vector3(bounds.end.x, bounds.end.y, z)),
		project(Vector3(bounds.position.x, bounds.end.y, z)),
	])


## Inverse of [method project] on the horizontal plane of [param layer_index].
##
## Returns (chunk x, chunk y, layer index): z is the layer axis, which is what the
## view reports to the author, not a world coordinate.
func unproject(screen_point: Vector2, layer_index: int) -> Vector3:
	var z := layer_z(layer_index)
	var world := world_scale()
	var cp := cos(pitch)
	var sp := sin(pitch)
	var u := screen_point.x - viewport_size.x * 0.5 - offset.x
	# v is the camera-space height times the projected scale.
	var v := viewport_size.y * 0.5 + offset.y - screen_point.y
	var denominator := v * sp - cp * world * FOCAL
	var y1 := 0.0
	if absf(denominator) > 0.00001:
		y1 = (z * sp * world * FOCAL + v * z * cp - v * FOCAL) / denominator
	var depth := y1 * sp - z * cp
	var k := FOCAL / maxf(1.2, FOCAL + depth)
	var projected := world * k
	var x1 := 0.0 if is_zero_approx(projected) else u / projected
	var cy := cos(yaw)
	var sy := sin(yaw)
	# Undo the yaw: [x1, y1] = R * [x, -y], so the floor-plan y is negated back.
	return Vector3(x1 * cy + y1 * sy, x1 * sy - y1 * cy, float(layer_index))


## Frames every layer: zoom and offset so all slabs fit the viewport.
## Returns false when there is nothing to frame.
func fit(layer_bounds: Array[Rect2]) -> bool:
	if layer_bounds.is_empty() or viewport_size.x <= 1.0 or viewport_size.y <= 1.0:
		return false
	var saved_zoom := zoom
	var saved_offset := offset
	zoom = 1.0
	offset = Vector2.ZERO
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	for layer_index: int in range(layer_bounds.size()):
		var bounds: Rect2 = layer_bounds[layer_index]
		var z := layer_z(layer_index)
		var corners: Array[Vector3] = [
			Vector3(bounds.position.x, bounds.position.y, z),
			Vector3(bounds.end.x, bounds.position.y, z),
			Vector3(bounds.end.x, bounds.end.y, z),
			Vector3(bounds.position.x, bounds.end.y, z),
			Vector3(bounds.position.x, bounds.position.y, z - SLAB_THICKNESS),
			Vector3(bounds.end.x, bounds.end.y, z + 0.12),
		]
		for corner: Vector3 in corners:
			var screen := project(corner)
			minimum = Vector2(minf(minimum.x, screen.x), minf(minimum.y, screen.y))
			maximum = Vector2(maxf(maximum.x, screen.x), maxf(maximum.y, screen.y))
	if not (is_finite(minimum.x) and is_finite(maximum.x)):
		zoom = saved_zoom
		offset = saved_offset
		return false
	var span := (maximum - minimum).max(Vector2.ONE)
	zoom = clampf(
		minf(viewport_size.x * FIT_WIDTH / span.x, viewport_size.y * FIT_HEIGHT / span.y),
		MIN_ZOOM,
		MAX_ZOOM
	)
	var center := (minimum + maximum) * 0.5
	offset = -(center - viewport_size * 0.5) * zoom + Vector2(0.0, 10.0)
	return true


## Layer index whose projected slab contains [param screen_point], nearest first.
## Returns -1 when the point is outside every layer.
func pick_layer(screen_point: Vector2, layer_bounds: Array[Rect2]) -> int:
	for layer_index: int in range(layer_bounds.size() - 1, -1, -1):
		if geometry_contains(slab_quad(layer_bounds[layer_index], layer_index), screen_point):
			return layer_index
	return -1


static func geometry_contains(polygon: PackedVector2Array, point: Vector2) -> bool:
	var inside := false
	var count := polygon.size()
	for index: int in range(count):
		var previous := polygon[(index + count - 1) % count]
		var current := polygon[index]
		var crosses := (current.y > point.y) != (previous.y > point.y)
		if not crosses:
			continue
		var denominator := previous.y - current.y
		if is_zero_approx(denominator):
			continue
		var x_at := (previous.x - current.x) * (point.y - current.y) / denominator + current.x
		if point.x < x_at:
			inside = not inside
	return inside
