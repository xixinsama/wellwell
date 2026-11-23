extends CanvasLayer
class_name CrtOverlay

## Full-screen CRT finish over every other canvas layer.
##
## Lives at the top of `main.tscn` and is switched by the `crt_enabled` video
## setting. The shader needs to know where the integer-scaled game pixel grid
## starts in window space, so this script pushes `screen_pixels`, `grid_origin`
## and `pixel_scale` whenever the viewport or the game container changes size.

const SETTINGS_PATH := NodePath("/root/GlobalSettings")
const DESIGN_SIZE := Vector2(320.0, 180.0)

@onready var screen_rect: ColorRect = get_node_or_null("Screen") as ColorRect

var _container: SubViewportContainer
var _material: ShaderMaterial
var _last_window := Vector2.ZERO
var _last_origin := Vector2.ZERO
var _last_scale := 0.0


func _ready() -> void:
	if screen_rect != null:
		_material = screen_rect.material as ShaderMaterial
	_container = get_node_or_null("../SubViewportContainer") as SubViewportContainer
	var settings := get_node_or_null(SETTINGS_PATH)
	if settings != null and settings.has_signal("settings_changed"):
		settings.connect("settings_changed", _refresh)
	get_viewport().size_changed.connect(_queue_layout)
	if _container != null:
		_container.resized.connect(_queue_layout)
	_refresh()
	_queue_layout()


func _queue_layout() -> void:
	# Main lays out the container from the same `size_changed` signal; deferring
	# reads the final position instead of the previous frame's.
	call_deferred("_update_layout")


func _update_layout() -> void:
	if _material == null:
		return
	var window := Vector2(get_viewport().get_visible_rect().size)
	var pixel_scale := 1.0
	var origin := Vector2.ZERO
	if _container != null and _container.stretch_shrink > 0:
		pixel_scale = float(_container.stretch_shrink)
		var viewport: SubViewport = null
		if _container.get_child_count() > 0:
			viewport = _container.get_child(0) as SubViewport
		# The safe 320x180 frame is inset by one viewport pixel (the 322x182
		# SubViewport border), so game pixel (0, 0) sits one upscale step inside
		# the container.
		var inset := Vector2.ONE * pixel_scale if viewport != null else Vector2.ZERO
		origin = _container.global_position + inset
	else:
		pixel_scale = maxf(1.0, floorf(minf(window.x / DESIGN_SIZE.x, window.y / DESIGN_SIZE.y)))
		origin = ((window - DESIGN_SIZE * pixel_scale) * 0.5).round()
	if window == _last_window and origin == _last_origin and is_equal_approx(pixel_scale, _last_scale):
		return
	_last_window = window
	_last_origin = origin
	_last_scale = pixel_scale
	_material.set_shader_parameter("screen_pixels", window)
	_material.set_shader_parameter("grid_origin", origin)
	_material.set_shader_parameter("pixel_scale", pixel_scale)


func _refresh() -> void:
	var settings := get_node_or_null(SETTINGS_PATH)
	if settings == null or not settings.has_method("get_value"):
		return
	visible = bool(settings.call("get_value", &"crt_enabled"))
