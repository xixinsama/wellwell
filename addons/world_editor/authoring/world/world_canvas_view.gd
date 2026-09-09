@tool
class_name WorldCanvasView
extends RefCounted

const MIN_ZOOM := 0.1
const MAX_ZOOM := 4.0

var view_center_world_pixels := Vector2.ZERO
var zoom := 1.0


func world_to_screen(world_pixels: Vector2, viewport_size: Vector2) -> Vector2:
	return (world_pixels - view_center_world_pixels) * zoom + viewport_size * 0.5


func screen_to_world(screen_position: Vector2, viewport_size: Vector2) -> Vector2:
	return (screen_position - viewport_size * 0.5) / zoom + view_center_world_pixels


func zoom_at(screen_position: Vector2, factor: float, viewport_size: Vector2) -> void:
	var anchored_world := screen_to_world(screen_position, viewport_size)
	zoom = clampf(zoom * factor, MIN_ZOOM, MAX_ZOOM)
	view_center_world_pixels = anchored_world - (screen_position - viewport_size * 0.5) / zoom


func pan_screen_delta(delta: Vector2) -> void:
	view_center_world_pixels -= delta / zoom


func fit_world_rect(rect: Rect2, viewport_size: Vector2, padding := 48.0) -> void:
	if not rect.has_area():
		reset()
		return
	var available := Vector2(
		maxf(1.0, viewport_size.x - padding * 2.0),
		maxf(1.0, viewport_size.y - padding * 2.0)
	)
	view_center_world_pixels = rect.get_center()
	zoom = clampf(minf(available.x / rect.size.x, available.y / rect.size.y), MIN_ZOOM, MAX_ZOOM)


func reset() -> void:
	view_center_world_pixels = Vector2.ZERO
	zoom = 1.0
