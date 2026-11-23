extends CanvasLayer
class_name CrtOverlay

## Full-screen CRT finish over every other canvas layer.
##
## Lives at the top of `main.tscn` and is switched by the `crt_enabled` video
## setting. The shader renders one elliptical phosphor dot per game pixel, so the
## script has to know where the integer-scaled game grid starts and how many window
## pixels one game pixel covers. It also precomputes the mean dot coverage at that
## upscale and hands it to the shader, which keeps the dot lattice
## brightness-neutral.

const SETTINGS_PATH := NodePath("/root/GlobalSettings")
const DESIGN_SIZE := Vector2(320.0, 180.0)

## Dot lattice tuning. Exposed here so the look can be changed in the inspector;
## the shader's dot_average is recomputed automatically.
@export_range(0.0, 0.9, 0.01) var dot_strength := 0.70
@export_range(0.3, 1.2, 0.01) var dot_size := 1.0
@export_enum("Scanline", "Phosphor Dots") var crt_mode := 1

@export_range(0.6, 2.0, 0.01) var dot_aspect := 1.15
@export_range(0.1, 0.9, 0.01) var dot_softness := 0.45

@onready var screen_rect: ColorRect = get_node_or_null("Screen") as ColorRect

var _container: SubViewportContainer
var _material: ShaderMaterial
var _last_window := Vector2.ZERO
var _last_origin := Vector2.ZERO
var _last_scale := 0.0
var _last_dot := Vector4.ZERO


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


func _process(_delta: float) -> void:
	# Lets the inspector tune the lattice while the game runs.
	if Vector4(dot_strength, dot_size, dot_aspect, dot_softness) != _last_dot:
		_push_dot_parameters()


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
		# The safe 320x180 frame is centred inside the SubViewport (1 px border in
		# the main scene, none in the smaller runner scenes). Convert that border
		# into window pixels so the dot lattice starts on game pixel (0, 0).
		var inset := Vector2.ZERO
		if viewport != null:
			inset = ((Vector2(viewport.size) - DESIGN_SIZE) * 0.5).floor() * pixel_scale
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
	_push_dot_parameters()


func _push_dot_parameters() -> void:
	if _material == null:
		return
	_last_dot = Vector4(dot_strength, dot_size, dot_aspect, dot_softness)
	_material.set_shader_parameter("dot_strength", dot_strength)
	_material.set_shader_parameter("dot_size", dot_size)
	_material.set_shader_parameter("dot_aspect", dot_aspect)
	_material.set_shader_parameter("dot_softness", dot_softness)
	_material.set_shader_parameter("dot_average", _dot_average(_last_scale))


## Mean coverage of the dot profile over one game pixel, sampled on the same
## n x n window-pixel grid the fragment shader evaluates. This is what keeps the
## average brightness identical when strength/size/aspect change.
func _dot_average(pixel_scale: float) -> float:
	var samples := int(clampf(pixel_scale, 1.0, 16.0))
	var total := 0.0
	for y: int in samples:
		for x: int in samples:
			var point := Vector2(
				(float(x) + 0.5) / float(samples) - 0.5,
				(float(y) + 0.5) / float(samples) - 0.5
			)
			point.y *= dot_aspect
			var distance := point.length() / maxf(0.5 * dot_size, 0.001)
			total += 1.0 - smoothstep(1.0 - dot_softness, 1.0, distance)
	return total / float(samples * samples)


func _refresh() -> void:
	var settings := get_node_or_null(SETTINGS_PATH)
	if settings != null and settings.has_method("get_value"):
		visible = bool(settings.call("get_value", &"crt_enabled"))
		var mode := String(settings.call("get_value", &"crt_mode"))
		if not mode.is_empty():
			crt_mode = 0 if mode == "scanline" else 1
	if _material != null:
		_material.set_shader_parameter("crt_mode", crt_mode)
