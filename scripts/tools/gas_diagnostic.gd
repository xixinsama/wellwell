extends SceneTree

## Gas layer diagnostic: dumps the exact input and output of the mist layer, so a
## claim about the gas ("the stipple breaks into vertical bars") can be checked
## against the pixels instead of argued about.
##
##   & godot --path . --resolution 1280x720 -s res://scripts/tools/gas_diagnostic.gd \
##       -- --scene res://scenes/levels/test/gas_lab_runner.tscn --out C:/tmp/gas \
##          --settle 2.0 --frames 6 --interval 0.4
##
## Per frame `i` (zero padded, spaced `--interval` seconds apart) it writes:
##   density_%02d.png   the simulation field, exactly as the render shader samples it
##   alpha_%02d.png     the gas layer alone: Atmosphere solo over a transparent
##                      background, so the alpha channel *is* what the mist adds
##   full_%02d.png      the frame as the game shows it, for reference
## plus, once:
##   info.txt           room rect, field size, mask size, the exported tuning and
##                      the field's own column/row means
##   light_map.png      the room light map the mist is lit by
##   mask_solid.png     the mask the render shader discards with
##
## The sequence matters: the plume thins over time, and the artifact is reported for
## the thin state, so a single still can easily miss it.
##
## Numbers in info.txt that matter for a stripe hunt:
##   column_mean_spread / row_mean_spread  how much the field's own columns differ
##                                         from each other, i.e. is the structure in
##                                         the simulation or added by the shader
##   alpha_mean / alpha_lit_fraction       how strong the layer is at that moment

const DEFAULT_SCENE := "res://scenes/levels/test/gas_lab_runner.tscn"
const DEFAULT_OUT := "user://gas_diagnostic"
const STIPPLE_TEXTURE_PATH := "res://resources/textures/blue_noise_64.png"

var _scene_path := DEFAULT_SCENE
var _out_dir := ""
var _settle := 2.0
var _frames := 1
var _interval := 0.4
var _stipple_modes: Array[float] = [-1.0]
var _uniform_overrides: Dictionary = {}
## Freeze the solver after the settle so several kernels see the same gas.
var _freeze := true
var _stipple_texture: Texture2D
var _world: Node
var _viewport: SubViewport
var _atmosphere: Node
var _light: Node


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_parse_arguments()
	_out_dir = _resolve_out_dir(_out_dir)
	DirAccess.make_dir_recursive_absolute(_out_dir)
	var scene: PackedScene = load(_scene_path) as PackedScene
	if scene == null:
		push_error("gas_diagnostic: cannot load %s" % _scene_path)
		quit(2)
		return
	root.add_child(scene.instantiate())
	await create_timer(_settle).timeout
	_viewport = _find_world_viewport(root)
	_world = _find_world(_viewport)
	_atmosphere = get_first_node_in_group(&"atmosphere")
	_light = get_first_node_in_group(&"light_field")
	if _viewport == null or _world == null or _atmosphere == null:
		push_error("gas_diagnostic: no viewport/world/atmosphere in %s" % _scene_path)
		quit(2)
		return
	# The game viewport has an opaque clear colour, so a capture of it is alpha = 1
	# everywhere and says nothing about how thick a layer is. A transparent target
	# makes each canvas item's coverage readable from the alpha channel: one layer on
	# its own then *is* the layer's opacity map.
	_viewport.transparent_bg = true
	print("gas_diagnostic: viewport=%dx%d atmosphere=%s" % [
		_viewport.size.x, _viewport.size.y, String(_atmosphere.name)
	])
	_write_info()
	_dump_light()
	_apply_uniform_overrides()
	# Comparing kernels only means something on the *same* gas: the field is still
	# evolving between captures, and a 0.6 s difference already changes the mean
	# opacity by a few percent. Freezing the Atmosphere's `_process` stops the
	# solver while the quad keeps drawing the textures it last wrote.
	if _freeze:
		_atmosphere.set_process(false)
		print("gas_diagnostic: froze the simulation for the capture")
	for mode: float in _stipple_modes:
		if mode >= 0.0:
			_apply_stipple(mode)
		for index: int in _frames:
			await _capture_frame(index, mode)
			if index + 1 < _frames:
				await create_timer(_interval).timeout
	print("gas_diagnostic: wrote %d frame(s) to %s" % [_frames * _stipple_modes.size(), _out_dir])
	quit(0)


## Sets `--uniform=key=value` on every simulation pass that declares `key`. The
## passes are the SubViewports the Atmosphere's solver owns, so this reaches the
## velocity, pressure, density and projection shaders without touching the room.
func _apply_uniform_overrides() -> void:
	if _uniform_overrides.is_empty():
		return
	var applied: Array[String] = []
	for material: ShaderMaterial in _shader_materials(_world):
		for key: String in _uniform_overrides:
			if material.shader.get_shader_uniform_list(true).any(
				func(entry: Dictionary) -> bool: return String(entry["name"]) == key
			):
				material.set_shader_parameter(key, _uniform_overrides[key])
				applied.append(key)
	print("gas_diagnostic: uniform overrides %s -> %s" % [str(_uniform_overrides), str(applied)])


## Every ShaderMaterial under the world: the simulation passes live on the
## SubViewports' ColorRects, the mist itself on the Atmosphere's quad.
func _shader_materials(node: Node) -> Array[ShaderMaterial]:
	var result: Array[ShaderMaterial] = []
	for child: Node in node.get_children():
		if child is CanvasItem:
			var material := (child as CanvasItem).material
			if material is ShaderMaterial and (material as ShaderMaterial).shader != null:
				result.append(material as ShaderMaterial)
		result.append_array(_shader_materials(child))
	return result


## Switches the mist's stylised threshold at runtime: 0 = the 4x4 ordered Bayer
## tile, 1 = the blue-noise tile, 2 = white noise. Capturing the same gas state
## under several kernels is the only honest way to say which one the owner is
## seeing, because the density field itself is identical between the captures.
func _apply_stipple(mode: float) -> void:
	var layer := _atmosphere.get_node_or_null("GasLayer") as MeshInstance2D
	if layer == null:
		push_warning("gas_diagnostic: the atmosphere has no GasLayer quad to re-kernel")
		return
	var material := layer.material as ShaderMaterial
	if material == null:
		return
	material.set_shader_parameter("stipple_mode", mode)
	if mode >= 0.5 and mode < 1.5 and _stipple_texture == null:
		_stipple_texture = load(STIPPLE_TEXTURE_PATH) as Texture2D
		if _stipple_texture == null:
			push_warning("gas_diagnostic: %s is missing; the blue-noise mode will read as white" % STIPPLE_TEXTURE_PATH)
		material.set_shader_parameter("stipple_tex", _stipple_texture)


func _parse_arguments() -> void:
	var arguments := OS.get_cmdline_user_args()
	var values: Dictionary = {}
	var index := 0
	while index < arguments.size():
		var argument: String = arguments[index]
		if argument.begins_with("--"):
			var key := argument.substr(2)
			var value := ""
			var equals := key.find("=")
			if equals >= 0:
				value = key.substr(equals + 1)
				key = key.substr(0, equals)
			elif index + 1 < arguments.size() and not arguments[index + 1].begins_with("--"):
				value = arguments[index + 1]
				index += 1
			values[key] = value
		index += 1
	if values.has("scene"):
		_scene_path = String(values["scene"])
	if values.has("out"):
		_out_dir = String(values["out"])
	if values.has("settle"):
		_settle = String(values["settle"]).to_float()
	if values.has("frames"):
		_frames = maxi(String(values["frames"]).to_int(), 1)
	if values.has("interval"):
		_interval = maxf(String(values["interval"]).to_float(), 0.0)
	if values.has("stipple"):
		_stipple_modes.clear()
		for token: String in String(values["stipple"]).split(",", false):
			_stipple_modes.append(token.strip_edges().to_float())
		if _stipple_modes.is_empty():
			_stipple_modes.append(-1.0)
	if values.has("freeze"):
		_freeze = String(values["freeze"]).to_int() != 0
	else:
		# Freezing exists for A/B captures of one gas state; a run that is watching
		# the gas evolve must keep stepping.
		_freeze = _stipple_modes.size() > 1
	if values.has("uniform"):		# --uniform=vorticity=10,detail_refresh=3 : poked into every simulation
		# pass that declares the parameter, so a solver knob can be A/B tested
		# without rebuilding the room.
		for entry: String in String(values["uniform"]).split(",", false):
			var pair := entry.split("=", false)
			if pair.size() == 2:
				_uniform_overrides[pair[0].strip_edges()] = pair[1].strip_edges().to_float()


func _resolve_out_dir(requested: String) -> String:
	if requested.is_empty():
		return ProjectSettings.globalize_path(DEFAULT_OUT)
	if requested.begins_with("res://") or requested.begins_with("user://"):
		return ProjectSettings.globalize_path(requested)
	return requested


func _capture_frame(index: int, mode: float) -> void:
	var suffix := "" if mode < 0.0 else "m%d_%02d" % [int(mode), index]
	var density: Image = _atmosphere.call("get_gas_image")
	if mode < 0.0 or mode == _stipple_modes[0]:
		if density != null and density.get_width() > 0:
			density.save_png("%s/density_%02d.png" % [_out_dir, index])
		# RG = the projected velocity in cells per second, B = the detail tracer.
		var velocity: Image = _atmosphere.call("get_gas_velocity_image")
		if velocity != null and velocity.get_width() > 0:
			velocity.save_png("%s/velocity_%02d.png" % [_out_dir, index])
	var solo := await _capture_with_only([_atmosphere])
	if solo != null:
		if mode < 0.0:
			solo.save_png("%s/alpha_%02d.png" % [_out_dir, index])
		else:
			solo.save_png("%s/alpha_%s.png" % [_out_dir, suffix])
		var stats := _alpha_stats(solo)
		print("frame %s: alpha mean %.4f, lit %.1f%%, columns %.5f rows %.5f" % [
			suffix if not suffix.is_empty() else "%02d" % index,
			stats["mean"], stats["lit"] * 100.0, stats["column_spread"], stats["row_spread"]
		])
	var full := await _capture_with_only([], false)
	if full != null:
		if mode < 0.0:
			full.save_png("%s/full_%02d.png" % [_out_dir, index])
		else:
			full.save_png("%s/full_%s.png" % [_out_dir, suffix])
	await _capture_window(index, suffix)


## The frame as the *window* shows it: the world viewport is upscaled 4x by its
## SubViewportContainer and then finished by the CRT overlay, so a capture of the
## world viewport is not what the owner looks at. This one includes both, and with
## `crt` in the frame's name pair (`window` / `window_nocrt`) it also answers
## whether the CRT's scanline/slot mask is what draws periodic structure.
func _capture_window(index: int, suffix: String) -> void:
	var name := "%02d" % index if suffix.is_empty() else suffix
	await process_frame
	await RenderingServer.frame_post_draw
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png("%s/window_%s.png" % [_out_dir, name])
	var crt := root.find_child("CrtOverlay", true, false)
	if crt == null or not crt is CanvasLayer:
		return
	var overlay := crt as CanvasLayer
	var previous := overlay.visible
	overlay.visible = false
	await process_frame
	await RenderingServer.frame_post_draw
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/window_nocrt_%s.png" % [_out_dir, name])
	overlay.visible = previous


## Captures the world viewport with only `keep` visible among the world's
## top-level children. With `solo = false` the visibility is left alone and the
## frame is captured as it is.
func _capture_with_only(keep: Array, solo := true) -> Image:
	var visibility: Dictionary = {}
	if solo:
		for child: Node in _world.get_children():
			if child is CanvasItem:
				var item := child as CanvasItem
				visibility[item] = item.visible
				item.visible = item in keep
	await process_frame
	await RenderingServer.frame_post_draw
	await process_frame
	await RenderingServer.frame_post_draw
	var image := _viewport.get_texture().get_image()
	for item: CanvasItem in visibility:
		item.visible = visibility[item]
	return image


## Column and row means of the gas alpha, plus the spread between them. A vertical
## stripe is a column whose mean is systematically off the room's mean, so the
## spread is the first number to look at; `faded` only measures the faint part.
func _alpha_stats(image: Image) -> Dictionary:
	var width := image.get_width()
	var height := image.get_height()
	var columns := PackedFloat64Array()
	columns.resize(width)
	var rows := PackedFloat64Array()
	rows.resize(height)
	var total := 0.0
	var lit := 0
	var low_total := 0.0
	var low_count := 0
	for y: int in height:
		for x: int in width:
			var value := image.get_pixel(x, y).a
			columns[x] += value
			rows[y] += value
			total += value
			if value > 0.02:
				lit += 1
			if value > 0.015 and value <= 0.06:
				low_total += value
				low_count += 1
	for x: int in width:
		columns[x] /= float(height)
	for y: int in height:
		rows[y] /= float(width)
	var mean := total / float(maxi(width * height, 1))
	return {
		"mean": mean,
		"lit": float(lit) / float(maxi(width * height, 1)),
		"column_spread": _spread(columns),
		"row_spread": _spread(rows),
		"faded": low_total / float(maxi(low_count, 1)),
		"verdict": "columns %.5f / rows %.5f" % [_spread(columns), _spread(rows)],
	}


func _spread(values: PackedFloat64Array) -> float:
	if values.is_empty():
		return 0.0
	var lowest := values[0]
	var highest := values[0]
	for value: float in values:
		lowest = minf(lowest, value)
		highest = maxf(highest, value)
	return highest - lowest


func _dump_light() -> void:
	if _light == null or not _light.has_method("get_light_image"):
		return
	var image: Variant = _light.call("get_light_image")
	if image is Image and (image as Image).get_width() > 0:
		(image as Image).save_png("%s/light_map.png" % _out_dir)


func _write_info() -> void:
	var rows: Array[String] = []
	rows.append("# gas diagnostic of %s" % _scene_path)
	rows.append("viewport\t%d x %d" % [_viewport.size.x, _viewport.size.y])
	rows.append("world\t%s" % String(_world.name))
	var state: Dictionary = _atmosphere.call("get_debug_state")
	for key: String in ["backend", "requested_backend", "fallback", "enabled", "sim_hz", "step_ms"]:
		rows.append("%s\t%s" % [key, str(state.get(key, ""))])
	var gas: Dictionary = state.get("gas", {})
	for key: String in ["size", "iterations", "passes_per_step", "steps"]:
		rows.append("gas.%s\t%s" % [key, str(gas.get(key, ""))])
	rows.append("room_rect\t%s" % str(_atmosphere.call("get_room_rect")))
	for property: String in [
		"gas_ambient", "gas_wind", "wind_gust", "wind_lift", "gas_decay", "gas_diffusion",
		"gas_refill", "gas_dissipation", "gas_buoyancy", "gas_viscosity", "pressure_iterations",
		"base_alpha", "light_alpha", "noise_amount", "gas_alpha", "push_radius", "push_strength",
	]:
		rows.append("%s\t%s" % [property, str(_atmosphere.get(property))])
	var mask: Variant = _atmosphere.call("get_gas_mask_image")
	if mask is Image and (mask as Image).get_width() > 0:
		(mask as Image).save_png("%s/mask_solid.png" % _out_dir)
		rows.append("mask\t%d x %d" % [(mask as Image).get_width(), (mask as Image).get_height()])
	_write_text("info.txt", "\n".join(rows) + "\n")
	print("\n".join(rows))


func _write_text(name: String, text: String) -> void:
	var file := FileAccess.open("%s/%s" % [_out_dir, name], FileAccess.WRITE)
	if file == null:
		push_warning("gas_diagnostic: cannot write %s" % name)
		return
	file.store_string(text)
	file.close()


func _find_world_viewport(from: Node) -> SubViewport:
	for child: Node in from.get_children():
		if child is SubViewportContainer:
			for grandchild: Node in (child as SubViewportContainer).get_children():
				if grandchild is SubViewport:
					return grandchild as SubViewport
	for child: Node in from.get_children():
		var found := _find_world_viewport(child)
		if found != null:
			return found
	return null


func _find_world(viewport: SubViewport) -> Node:
	if viewport == null:
		return null
	for child: Node in viewport.get_children():
		if child is CanvasItem:
			return child
	return null
