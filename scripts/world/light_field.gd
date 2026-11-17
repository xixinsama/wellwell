@tool
class_name LightField
extends Node2D

## Room-wide 2D light map, and the single source of light for every system.
##
## Godot's 2D lights cannot be read back by a custom shader, so the field is
## rendered into its own room-sized SubViewport: additive PointLight2D nodes over
## a black canvas, which yields falloff *and* real shadows from LightOccluder2D
## polygons for free on the GPU. Nothing is read back on the CPU (a readback
## stalls the pipeline), so every consumer just samples the viewport texture:
##
## - this node's own shade pass darkens what the lights do not reach,
## - this node's glow pass adds the warm light back on top,
## - FogOfWar pushes its tendrils back inside the light,
## - TerrainHighlight only lights the rim where the light reaches.
##
## Bound through WorldSession.register_room_extension like the fog: the room
## binding rebuilds the viewport, the lights, the shade/glow quads and the terrain
## occluders, so one field always describes exactly one room.
##
## Occluders are built from the `SolidTiles` collision polygons (the same source
## the terrain outline uses), merged into long runs so a wall costs one occluder
## per straight edge instead of one per tile.

const LIGHT_GROUP := &"fog_light"
const FOG_SHADER: Shader = preload("res://scripts/shaders/light_overlay.gdshader")
const GLOW_SHADER: Shader = preload("res://scripts/shaders/light_glow.gdshader")
## Half width of the radial falloff texture; PointLight2D.texture_scale is
## expressed in fractions of this.
const LIGHT_TEXTURE_RADIUS := 64.0
## Longest edge run kept as one occluder; longer runs are split to keep the
## shadow pass bounded.
const OCCLUDER_RUN_LIMIT := 160
## Share of a light texture that stays at full brightness before the falloff.
const PLATEAU := 0.42
## Authored lights are built as a visible ring plus a dim spill that reaches
## `AUTHORED_REACH` times further, which is what makes their cast shadows long
## enough to cross the room.
const AUTHORED_REACH := 3.2
const AUTHORED_SPILL := 0.25

@export var player_path: NodePath
@export_group("Lantern")
## Radius of the large ring in pixels (the default is 3.25 tiles).
@export_range(8.0, 200.0, 1.0) var halo_radius := 26.0
## Radius of the small bright ring in pixels.
@export_range(2.0, 64.0, 0.5) var core_radius := 9.0
@export_range(0.0, 4.0, 0.05) var halo_energy := 0.75
@export_range(0.0, 4.0, 0.05) var core_energy := 1.1
@export var light_color := Color(1.0, 0.87, 0.66, 1.0)
## Falloff curve of both rings; 1 is linear, higher values keep the rim softer.
@export_range(0.4, 4.0, 0.05) var falloff_power := 1.7
## Softness of the terrain shadows.
@export_range(0.0, 10.0, 0.5) var shadow_softness := 2.0
## Atlas cell of the glass tile: it has collision but lets light through, like it
## lets sight through in the fog.
@export var glass_tile_atlas := Vector2i(0, 3)
## Room-scale light under the lantern. The two rings are the visible lamp; this
## dim light reaches across the room, which is what makes the cast shadows long
## and lifts the far corners instead of leaving them black.
@export_range(0.0, 400.0, 5.0) var reach_radius := 170.0
@export_range(0.0, 1.0, 0.01) var reach_energy := 0.35
## Fuzzy rim: how far the lit side is pushed outwards in pixels (0 = a clean
## circle). Only ever adds light, so the dark side never eats inwards.
@export_range(0.0, 6.0, 0.1) var rim_fuzz := 2.0
## Size of one hair in pixels; smaller is denser.
@export_range(0.5, 8.0, 0.1) var rim_fuzz_scale := 2.2

@export_group("Room Light")
## Light that reaches everything, added on top of the light map.
@export_range(0.0, 1.0, 0.01) var ambient := 0.55
## How much of the light map is added back as warm glow (0 = shade only).
@export_range(0.0, 2.0, 0.01) var glow_gain := 0.15
@export var glow_color := Color(1.0, 0.86, 0.62, 1.0)
## Dither amount on the shade falloff. 0 keeps the shade a plain brightness
## multiply; anything above turns the unlit area into a halftone pattern.
@export_range(0.0, 1.0, 0.01) var dither_strength := 0.0
@export_group("Shadow Bounce")
## Share of the light next to a shadow that bleeds into it, so a cast shadow is
## dark deep inside and lighter near its silhouette.
@export_range(0.0, 1.0, 0.01) var shadow_bounce := 0.45
## How far the bounce reaches in pixels.
@export_range(1.0, 40.0, 0.5) var bounce_radius := 10.0
## Draw order of the two overlay quads. The fog sits at 10, so both stay below it
## or the shadow would cover the unexplored area.
@export var shade_order := 8
@export var glow_order := 9

## Collect authored FogLight nodes into the same map.
@export var use_authored_lights := true
## Cast terrain shadows. Turning it off keeps the light but removes the occluders.
@export var shadows := true

var _room_pixels := Vector2i.ZERO
var _room_origin_pixels := Vector2i.ZERO
var _room_bound := false
var _player: Node2D
var _viewport: SubViewport
var _canvas_root: Node2D
var _core_light: PointLight2D
var _halo_light: PointLight2D
var _reach_light: PointLight2D
var _authored: Array[Dictionary] = []
var _occluders: Node2D
var _shade: Sprite2D
var _glow: Sprite2D
var _texture: Texture2D
var _shade_material: ShaderMaterial
var _glow_material: ShaderMaterial
var _consumers: Array[Node] = []
var _texture_ring: ImageTexture
var _texture_spill: ImageTexture


var _start_time := 0.0


func _ready() -> void:
	_start_time = float(Time.get_ticks_msec()) / 1000.0
	add_to_group(&"light_field")
	if player_path != NodePath():
		_player = get_node_or_null(player_path) as Node2D
	set_process(true)


func _process(_delta: float) -> void:
	if not _room_bound:
		return
	_update_lantern()
	_update_authored_lights()


func bind_player(player: Node2D) -> void:
	_player = player


## WorldSession room extension entry point.
func bind_room(room_data: Variant, terrain_root: Node, origin_chunk: Variant = null) -> bool:
	return bind_room_with_origin(
		room_data, terrain_root, Vector2i(origin_chunk) if origin_chunk != null else Vector2i.ZERO
	)


func bind_room_with_origin(room_data: Variant, terrain_root: Node, origin_chunk: Vector2i) -> bool:
	if room_data == null or terrain_root == null:
		return false
	var chunks: Vector2i = room_data.get("room_size_chunks") if room_data.get("room_size_chunks") != null else Vector2i.ONE
	if chunks.x <= 0 or chunks.y <= 0:
		chunks = Vector2i.ONE
	clear_room()
	_room_origin_pixels = origin_chunk * Vector2i(320, 180)
	_room_pixels = chunks * Vector2i(320, 180)
	_room_bound = true
	_build_viewport()
	_build_lantern()
	_build_overlays()
	if shadows:
		_build_occluders(terrain_root)
	_collect_authored_lights()
	_bind_consumers()
	return true


func clear_room() -> void:
	_room_bound = false
	_authored.clear()
	_consumers.clear()
	for node: Node in [_shade, _glow, _occluders, _viewport]:
		if not is_instance_valid(node):
			continue
		if node.get_parent() != null:
			node.get_parent().remove_child(node)
		node.queue_free()
	_shade = null
	_glow = null
	_occluders = null
	_canvas_root = null
	_viewport = null
	_core_light = null
	_halo_light = null
	_reach_light = null
	_texture = null
	_room_pixels = Vector2i.ZERO


## The light map other systems sample. Null before the first room binding.
func get_light_texture() -> Texture2D:
	return _texture


func get_light_pixels() -> Vector2i:
	return _room_pixels


func get_ambient() -> float:
	return ambient


func is_room_bound() -> bool:
	return _room_bound


## Luminance of the light map at a world position, in 0..1 (ambient excluded).
## Debug and test helper; the shaders sample the texture directly.
func sample_light_at(world_position: Vector2) -> float:
	var local := Vector2i(world_position) - _room_origin_pixels
	if _room_pixels.x <= 0 or local.x < 0 or local.y < 0:
		return 0.0
	if local.x >= _room_pixels.x or local.y >= _room_pixels.y:
		return 0.0
	var image := _viewport.get_texture().get_image() if _viewport != null else null
	if image == null or image.is_empty():
		return 0.0
	var colour := image.get_pixel(local.x, local.y)
	return clampf(colour.r * 0.3 + colour.g * 0.59 + colour.b * 0.11, 0.0, 1.0)


func get_occluder_count() -> int:
	return _occluders.get_child_count() if _occluders != null else 0


func _build_viewport() -> void:
	_viewport = SubViewport.new()
	_viewport.name = "LightViewport"
	_viewport.size = _room_pixels
	_viewport.transparent_bg = true
	_viewport.disable_3d = true
	_viewport.msaa_2d = Viewport.MSAA_DISABLED
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	# Black canvas: additive lights are the only thing that shows up, which is
	# exactly the light map the shaders want.
	var modulate := CanvasModulate.new()
	modulate.color = Color(0.0, 0.0, 0.0, 1.0)
	_viewport.add_child(modulate)
	_canvas_root = Node2D.new()
	_canvas_root.name = "Lights"
	_viewport.add_child(_canvas_root)
	# A white quad that is *lit* turns the light accumulation into a texture.
	var catcher := ColorRect.new()
	catcher.name = "LightCatcher"
	catcher.color = Color(1.0, 1.0, 1.0, 1.0)
	catcher.size = Vector2(_room_pixels)
	catcher.position = Vector2.ZERO
	catcher.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_viewport.add_child(catcher)
	_texture = _viewport.get_texture()


func _build_lantern() -> void:
	_core_light = _make_light(core_radius, core_energy, light_color, false)
	_halo_light = _make_light(halo_radius, halo_energy, light_color, false)
	_reach_light = _make_light(reach_radius, reach_energy, light_color, true)
	_update_lantern()


func _make_light(radius: float, energy: float, colour: Color, spill: bool) -> PointLight2D:
	var light := PointLight2D.new()
	light.texture = _light_texture(spill)
	light.texture_scale = maxf(radius, 1.0) / LIGHT_TEXTURE_RADIUS
	light.energy = energy
	light.color = colour
	light.shadow_enabled = shadows
	light.shadow_filter = Light2D.SHADOW_FILTER_PCF5
	light.shadow_filter_smooth = shadow_softness
	_canvas_root.add_child(light)
	return light


func _light_texture(spill: bool) -> ImageTexture:
	if spill:
		if _texture_spill == null:
			_texture_spill = _radial_texture(0.0, 1.25)
		return _texture_spill
	if _texture_ring == null:
		_texture_ring = _radial_texture(PLATEAU, falloff_power)
	return _texture_ring


## Round radial falloff built as a GradientTexture2D, so the lamp itself is a
## clean circle: all of the fuzz happens later, on the lit side only.
##
## A plateau followed by `plateau`-relative falloff makes the lantern read as a
## bright disc plus a halo; the spill profile has no plateau at all, so it is one
## long dim gradient that reaches across the room.
func _radial_texture(plateau_value: float, power: float) -> ImageTexture:
	var stops := 12
	var offsets := PackedFloat32Array()
	var colors := PackedColorArray()
	for index: int in stops:
		var t := float(index) / float(stops - 1)
		var alpha := 1.0
		if t > plateau_value:
			var span := maxf(1.0 - plateau_value, 0.001)
			alpha = pow(clampf(1.0 - (t - plateau_value) / span, 0.0, 1.0), power)
		offsets.append(t)
		colors.append(Color(1.0, 1.0, 1.0, alpha))
	var gradient := Gradient.new()
	gradient.offsets = offsets
	gradient.colors = colors
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = int(LIGHT_TEXTURE_RADIUS * 2.0)
	texture.height = int(LIGHT_TEXTURE_RADIUS * 2.0)
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	return ImageTexture.create_from_image(texture.get_image())


func _update_lantern() -> void:
	if _core_light == null or _halo_light == null or _reach_light == null:
		return
	var local := Vector2.ZERO
	if is_instance_valid(_player):
		local = _player.global_position - Vector2(_room_origin_pixels)
		local = Vector2(local.round())
	for light: PointLight2D in [_core_light, _halo_light, _reach_light]:
		light.position = local
		light.color = light_color
		light.shadow_enabled = shadows
	_core_light.texture_scale = maxf(core_radius, 1.0) / LIGHT_TEXTURE_RADIUS
	_halo_light.texture_scale = maxf(halo_radius, 1.0) / LIGHT_TEXTURE_RADIUS
	_reach_light.texture_scale = maxf(reach_radius, 1.0) / LIGHT_TEXTURE_RADIUS
	_core_light.energy = core_energy
	_halo_light.energy = halo_energy
	_reach_light.energy = reach_energy


## Collects the authored lights into the field: RoomLight drives the whole light
## (motion, energy, shadows), the older FogLight keeps the mist's own falloff.
func _collect_authored_lights() -> void:
	_authored.clear()
	if not use_authored_lights or not is_inside_tree():
		return
	var room_rect := Rect2(Vector2(_room_origin_pixels), Vector2(_room_pixels))
	for group: StringName in [&"room_light", LIGHT_GROUP]:
		for node: Node in get_tree().get_nodes_in_group(group):
			if not is_instance_valid(node) or not (node is Node2D):
				continue
			var light_node := node as Node2D
			if not room_rect.has_point(light_node.global_position):
				continue
			var radius := float(light_node.get("radius")) if "radius" in light_node else 64.0
			var energy := float(light_node.get("energy")) if "energy" in light_node else 1.0
			var colour: Color = light_node.get("color") if "color" in light_node else light_color
			var casts := bool(light_node.get("casts_shadows")) if "casts_shadows" in light_node else true
			var radii := [radius, radius * AUTHORED_REACH]
			var energies := [energy, energy * AUTHORED_SPILL]
			var lights: Array[PointLight2D] = []
			for index: int in 2:
				var light := _make_light(
					float(radii[index]),
					float(energies[index]),
					Color(colour.r, colour.g, colour.b, 1.0),
					index == 1
				)
				light.shadow_enabled = shadows and casts
				lights.append(light)
			_authored.append({
				"node": light_node,
				"lights": lights,
				"base_energy": energy,
				"radius": radius,
			})


func _update_authored_lights() -> void:
	if _authored.is_empty():
		return
	var now := float(Time.get_ticks_msec()) / 1000.0 - _start_time
	for entry: Dictionary in _authored:
		var node: Node = entry["node"]
		var lights: Array = entry["lights"]
		if not is_instance_valid(node) or lights.is_empty():
			continue
		if node.has_method("get_light_state"):
			var state: Dictionary = node.call("get_light_state", now)
			var position := Vector2(state["position"]) - Vector2(_room_origin_pixels)
			var ring: PointLight2D = lights[0]
			var spill: PointLight2D = lights[1]
			ring.position = position
			spill.position = position
			ring.energy = float(state["energy"])
			spill.energy = float(state["energy"]) * AUTHORED_SPILL
			ring.color = Color(state["color"])
			spill.color = Color(state["color"])
			ring.texture_scale = maxf(float(state["radius"]), 1.0) / LIGHT_TEXTURE_RADIUS
			spill.texture_scale = (
				maxf(float(state["radius"]) * AUTHORED_REACH, 1.0) / LIGHT_TEXTURE_RADIUS
			)
			continue
		var plain_position := (node as Node2D).global_position - Vector2(_room_origin_pixels)
		var value := float(entry["base_energy"])
		var colour: Variant = null
		if node.has_method("get_energy_at"):
			value = float(node.call("get_energy_at", now))
		elif node.has_method("get_light_color"):
			colour = node.call("get_light_color")
		for index: int in lights.size():
			var light: PointLight2D = lights[index]
			light.position = plain_position
			light.energy = value * (1.0 if index == 0 else AUTHORED_SPILL)
			if colour != null:
				light.color = Color(colour)


func _build_overlays() -> void:
	_shade = Sprite2D.new()
	_shade.name = "LightShade"
	_shade.centered = false
	_shade.texture = _texture
	_shade.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_shade.z_index = shade_order
	_shade.z_as_relative = false
	_shade_material = ShaderMaterial.new()
	_shade_material.shader = FOG_SHADER
	_shade.material = _shade_material
	add_child(_shade)

	_glow = Sprite2D.new()
	_glow.name = "LightGlow"
	_glow.centered = false
	_glow.texture = _texture
	_glow.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_glow.z_index = glow_order
	_glow.z_as_relative = false
	_glow_material = ShaderMaterial.new()
	_glow_material.shader = GLOW_SHADER
	_glow.material = _glow_material
	add_child(_glow)


	_sync_overlays()
	_paint_overlay_parameters()


func _sync_overlays() -> void:
	for sprite: Sprite2D in [_shade, _glow]:
		if not is_instance_valid(sprite):
			continue
		sprite.texture = _texture
		sprite.position = to_local(Vector2(_room_origin_pixels))


func _paint_overlay_parameters() -> void:
	if _shade_material != null:
		_shade_material.set_shader_parameter("light_tex", _texture)
		_shade_material.set_shader_parameter("light_pixels", Vector2(_room_pixels))
		_shade_material.set_shader_parameter("ambient", ambient)
		_shade_material.set_shader_parameter("dither_strength", dither_strength)
		_shade_material.set_shader_parameter("bounce", shadow_bounce)
		_shade_material.set_shader_parameter("bounce_radius", bounce_radius)
		_shade_material.set_shader_parameter("rim_fuzz", rim_fuzz)
		_shade_material.set_shader_parameter("rim_fuzz_scale", rim_fuzz_scale)
		_shade_material.set_shader_parameter("shade_color", Color(0.0, 0.0, 0.0, 1.0))
	if _glow_material != null:
		_glow_material.set_shader_parameter("light_tex", _texture)
		_glow_material.set_shader_parameter("light_pixels", Vector2(_room_pixels))
		_glow_material.set_shader_parameter("glow_color", glow_color)
		_glow_material.set_shader_parameter("glow_gain", glow_gain)
		_glow_material.set_shader_parameter("rim_fuzz", rim_fuzz)
		_glow_material.set_shader_parameter("rim_fuzz_scale", rim_fuzz_scale)


func _build_occluders(terrain_root: Node) -> void:
	_occluders = Node2D.new()
	_occluders.name = "LightOccluders"
	_viewport.add_child(_occluders)
	var layer := terrain_root.get_node_or_null("Terrain/SolidTiles") as TileMapLayer
	if layer == null:
		return
	var solid := {}
	for cell: Vector2i in layer.get_used_cells():
		# Glass has collision but passes light, exactly like it passes sight in the
		# fog, so it is never an occluder.
		if layer.get_cell_atlas_coords(cell) == glass_tile_atlas:
			continue
		var data := layer.get_cell_tile_data(cell)
		if data == null:
			continue
		var blocks := false
		var physics_layers := layer.tile_set.get_physics_layers_count() if layer.tile_set != null else 1
		for physics_layer: int in physics_layers:
			if data.get_collision_polygons_count(physics_layer) > 0:
				blocks = true
				break
		if blocks:
			solid[cell] = true
	# Cells are room-local: the room's own node is what the lights are measured
	# from, so only the layer's offset inside the room survives.
	var offset := layer.global_position - (terrain_root as Node2D).global_position
	_emit_occluders(solid, layer, offset)


## Turns the solid map into long occluder runs: one segment per straight edge
## where a solid cell touches open air, so a wall costs one occluder instead of
## one per tile. `offset` moves the room-local cell grid onto the layer.
func _emit_occluders(solid: Dictionary, layer: TileMapLayer, offset: Vector2) -> void:
	var cell := float(layer.tile_set.tile_size.x) if layer.tile_set != null else 8.0
	if cell <= 0.0:
		cell = 8.0
	var runs := {"h": {}, "v": {}}
	for cell_pos: Vector2i in solid:
		var base := Vector2(cell_pos) * cell
		if not solid.has(cell_pos + Vector2i(0, -1)):
			_record_edge(runs, "h", base.y, base.x)
		if not solid.has(cell_pos + Vector2i(0, 1)):
			_record_edge(runs, "h", base.y + cell, base.x)
		if not solid.has(cell_pos + Vector2i(-1, 0)):
			_record_edge(runs, "v", base.x, base.y)
		if not solid.has(cell_pos + Vector2i(1, 0)):
			_record_edge(runs, "v", base.x + cell, base.y)
	for axis: String in runs:
		var lines: Dictionary = runs[axis]
		for line_key: int in lines:
			var starts: Array = lines[line_key]
			starts.sort()
			var span_start: int = starts[0]
			var span_end: int = starts[0]
			for index: int in range(1, starts.size()):
				var value: int = starts[index]
				if value == span_end + int(cell) and (span_end - span_start) < OCCLUDER_RUN_LIMIT:
					span_end = value
					continue
				_push_occluder(axis, float(line_key), float(span_start), float(span_end + int(cell)), offset)
				span_start = value
				span_end = value
			_push_occluder(axis, float(line_key), float(span_start), float(span_end + int(cell)), offset)


func _record_edge(runs: Dictionary, axis: String, line: float, start: float) -> void:
	var lines: Dictionary = runs[axis]
	var key := int(round(line))
	if not lines.has(key):
		lines[key] = []
	(lines[key] as Array).append(int(round(start)))


func _push_occluder(axis: String, line: float, from: float, to: float, offset: Vector2) -> void:
	var shape := OccluderPolygon2D.new()
	if axis == "h":
		shape.polygon = PackedVector2Array([
			Vector2(from, line) + offset, Vector2(to, line) + offset
		])
	else:
		shape.polygon = PackedVector2Array([
			Vector2(line, from) + offset, Vector2(line, to) + offset
		])
	shape.closed = false
	shape.cull_mode = OccluderPolygon2D.CULL_DISABLED
	var occluder := LightOccluder2D.new()
	occluder.occluder = shape
	_occluders.add_child(occluder)


## Hands the light map to every system that knows how to take it.
func _bind_consumers() -> void:
	_consumers.clear()
	if not is_inside_tree():
		return
	for group: StringName in [
		&"fog_of_war", &"terrain_highlight", &"water_field", &"atmosphere"
	]:
		for node: Node in get_tree().get_nodes_in_group(group):
			if not is_instance_valid(node) or not node.has_method("set_light_field"):
				continue
			node.call("set_light_field", _texture, _room_pixels, _room_origin_pixels)
			if not _consumers.has(node):
				_consumers.append(node)


func get_consumers() -> Array[Node]:
	return _consumers
