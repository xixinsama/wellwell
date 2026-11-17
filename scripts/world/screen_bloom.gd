class_name ScreenBloom
extends Node2D

## Screen-space bloom: threshold the brightest pixels of the world viewport, blur
## them horizontally, blur them vertically, then add the result back.
##
## Three half-resolution `SubViewport`s chained by their own textures, plus the
## additive quad that draws the last one over the world. Reading the world
## viewport's texture happens one frame late (a viewport cannot sample itself while
## it is being drawn), which is invisible for a glow.
##
## The composite quad stays in the world canvas under the fog, so the unexplored
## area keeps its black, and follows the camera so a room bigger than the screen
## still blooms over exactly the right pixels.

const BRIGHT_SHADER: Shader = preload("res://scripts/shaders/bloom_bright.gdshader")
const BLUR_SHADER: Shader = preload("res://scripts/shaders/bloom_blur.gdshader")
const COMPOSITE_SHADER: Shader = preload("res://scripts/shaders/bloom_composite.gdshader")

## Half resolution: the blur does not need the full grid.
const DOWNSCALE := 2

## Everything brighter than this blooms, 0..1.
@export_range(0.0, 1.0, 0.01) var threshold := 0.62
## Soft knee, so a pixel just over the threshold does not pop.
@export_range(0.0, 1.0, 0.01) var knee := 0.12
## How strong the bright pass is.
@export_range(0.0, 3.0, 0.01) var intensity := 1.0
## Blur radius in half-resolution texels.
@export_range(0.0, 24.0, 0.5) var radius := 6.0
## How much of the blurred bright pass is added back.
@export_range(0.0, 3.0, 0.01) var strength := 0.85
@export var tint := Color(1.0, 0.94, 0.86, 1.0)
## Ordered dither levels on the composite; 0 keeps the glow smooth.
@export_range(0.0, 32.0, 1.0) var levels := 6.0
## Draw order of the composite quad. The fog is at 10.
@export_range(-10, 20, 1) var draw_order := 9

var _bright: SubViewport
var _blur_v: SubViewport
var _quad: Sprite2D
var _bright_material: ShaderMaterial
var _blur_material_v: ShaderMaterial
var _composite_material: ShaderMaterial
var _buffer := Vector2i.ZERO
var _world_size := Vector2i.ZERO


func _ready() -> void:
	_build()
	set_process(true)


func _process(_delta: float) -> void:
	if _bright == null or not is_inside_tree():
		return
	var world := get_viewport()
	if world == null:
		return
	if world.size != _world_size:
		_world_size = world.size
		_resize(_world_size)
	_follow_camera(world.size)
	# The world viewport, one frame late. The bright pass also blurs
	# horizontally, so only the vertical pass is left to chain.
	_bright_material.set_shader_parameter("source", world.get_texture())
	_blur_material_v.set_shader_parameter("source", _bright.get_texture())
	_push_parameters()


func _build() -> void:
	_world_size = get_viewport().size if is_inside_tree() else Vector2i(322, 182)
	_buffer = _buffer_for(_world_size)
	_bright = _make_viewport("BloomBright", _buffer)
	_blur_v = _make_viewport("BloomBlurV", _buffer)

	_bright_material = _make_material(BRIGHT_SHADER)
	_bright_material.set_shader_parameter("direction", Vector2(1.0, 0.0))
	_bright.add_child(_make_rect(_bright_material, _buffer))
	_blur_material_v = _make_material(BLUR_SHADER)
	_blur_material_v.set_shader_parameter("direction", Vector2(0.0, 1.0))
	_blur_v.add_child(_make_rect(_blur_material_v, _buffer))

	_composite_material = _make_material(COMPOSITE_SHADER)
	_composite_material.set_shader_parameter("source", _blur_v.get_texture())
	_quad = Sprite2D.new()
	_quad.name = "BloomComposite"
	_quad.centered = false
	_quad.texture = _blur_v.get_texture()
	_quad.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_quad.z_index = draw_order
	_quad.z_as_relative = false
	_quad.material = _composite_material
	add_child(_quad)
	_follow_camera(_world_size)
	_push_parameters()


## Keeps the additive quad covering exactly what the camera sees.
func _follow_camera(world_size: Vector2i) -> void:
	if _quad == null:
		return
	var top_left := Vector2.ZERO
	var view_size := Vector2(world_size)
	var camera := get_viewport().get_camera_2d()
	if camera != null:
		view_size = Vector2(world_size) / camera.zoom
		top_left = camera.get_screen_center_position() - view_size * 0.5
	top_left = top_left.round()
	_quad.position = top_left
	if _buffer.x > 0 and _buffer.y > 0:
		_quad.scale = view_size / Vector2(_buffer)


func _push_parameters() -> void:
	_bright_material.set_shader_parameter("threshold", threshold)
	_bright_material.set_shader_parameter("knee", knee)
	_bright_material.set_shader_parameter("intensity", intensity)
	var texel := Vector2(1.0 / float(maxi(_buffer.x, 1)), 1.0 / float(maxi(_buffer.y, 1)))
	for material: ShaderMaterial in [_bright_material, _blur_material_v]:
		if material == null:
			continue
		material.set_shader_parameter("texel_size", texel)
		material.set_shader_parameter("radius", radius)
	_composite_material.set_shader_parameter("strength", strength)
	_composite_material.set_shader_parameter("tint", tint)
	_composite_material.set_shader_parameter("levels", levels)


func _resize(world_size: Vector2i) -> void:
	_buffer = _buffer_for(world_size)
	for viewport: SubViewport in [_bright, _blur_v]:
		viewport.size = _buffer
		for child: Node in viewport.get_children():
			if child is ColorRect:
				(child as ColorRect).size = Vector2(_buffer)


func _buffer_for(world_size: Vector2i) -> Vector2i:
	return Vector2i(
		maxi(world_size.x / DOWNSCALE, 1), maxi(world_size.y / DOWNSCALE, 1)
	)


func _make_viewport(node_name: String, size: Vector2i) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.name = node_name
	viewport.size = size
	viewport.transparent_bg = true
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	return viewport


func _make_rect(material: ShaderMaterial, size: Vector2i) -> ColorRect:
	var rect := ColorRect.new()
	rect.color = Color(1.0, 1.0, 1.0, 1.0)
	rect.position = Vector2.ZERO
	rect.size = Vector2(size)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.material = material
	return rect


func _make_material(shader: Shader) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = shader
	return material
