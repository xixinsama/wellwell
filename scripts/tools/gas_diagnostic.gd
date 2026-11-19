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
## --paint=x,y: pour gas from the room's GasBrush at that world position for
## --paint-seconds, moving along a small circle so the emitted gas gets a real
## velocity and the solver has something to advect.
var _paint_center := Vector2(-9999.0, -9999.0)
var _paint_seconds := 1.2
var _paint_radius := 18.0
## --paint-to=x,y: swipe the brush from --paint to here instead of circling.
var _paint_to := Vector2(-9999.0, -9999.0)
var _paint_channel := 2.0
## --warp=x,y: move the OS cursor to that window position and report the world
## position the brush derives from it, which is the whole screen-to-gas path.
var _warp_point := Vector2(-9999.0, -9999.0)
## --walk=x,y: after the first capture, move the player there so the camera shows a
## different part of the same field.
var _walk_point := Vector2(-9999.0, -9999.0)
## --press: after --warp, press and release the left button through the real input
## path and report whether the brush started painting.
var _press := false
## --cell=N: world pixels per simulation cell. Has to be set on the Atmosphere
## *before* the scene is added to the tree, because the field is rebuilt when the
## room binds (and cannot be resized afterwards).
var _cell_pixels := -1.0
## --timing: measure the uncapped frame cost at the end of the run.
var _timing := false
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
	var instance := scene.instantiate()
	if _cell_pixels > 0.0:
		# The field is sized when the room binds, which happens in `_ready`, so the
		# cell size has to be on the Atmosphere before the scene enters the tree.
		for node: Node in _all_nodes(instance):
			if node.has_method("bind_room_with_origin") and "gas_cell_pixels" in node:
				node.set("gas_cell_pixels", _cell_pixels)
				print("gas_diagnostic: cell size %.1f px" % _cell_pixels)
	root.add_child(instance)
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
	if _paint_center.x > -9999.0:
		await _paint()
	if _warp_point.x > -9999.0:
		await _check_warp()
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
				if _walk_point.x > -9999.0 and index == 0:
					await _walk()
				await create_timer(_interval).timeout
	print("gas_diagnostic: wrote %d frame(s) to %s" % [_frames * _stipple_modes.size(), _out_dir])
	if _timing:
		await _measure_frame_ms()
	quit(0)


## Frame cost with the field running, uncapped and without vsync, as the mean of a
## few passes. Used to compare resolutions: the solver's own `step_ms` only covers the
## submit side, and the GPU work of 20 passes shows up here.
func _measure_frame_ms() -> void:
	var previous_fps := Engine.max_fps
	var previous_vsync := DisplayServer.window_get_vsync_mode()
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_atmosphere.set_process(true)
	var best := INF
	for pass_index: int in 3:
		await process_frame
		await RenderingServer.frame_post_draw
		var started := Time.get_ticks_usec()
		for index: int in 120:
			await process_frame
			await RenderingServer.frame_post_draw
		best = minf(best, float(Time.get_ticks_usec() - started) / 1000.0 / 120.0)
	var state: Dictionary = _atmosphere.call("get_debug_state")
	var size: Vector2i = state.get("gas", {}).get("size", Vector2i.ZERO)
	print("gas_diagnostic: field %dx%d, %.3f ms/frame (best of 3, uncapped)" % [
		size.x, size.y, best
	])
	Engine.max_fps = previous_fps
	DisplayServer.window_set_vsync_mode(previous_vsync)


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
	if values.has("paint"):
		_paint_center = _parse_point(String(values["paint"]))
	if values.has("paint-seconds"):
		_paint_seconds = maxf(String(values["paint-seconds"]).to_float(), 0.1)
	if values.has("paint-to"):
		_paint_to = _parse_point(String(values["paint-to"]))
	if values.has("paint-radius"):
		_paint_radius = maxf(String(values["paint-radius"]).to_float(), 0.0)
	if values.has("paint-channel"):
		_paint_channel = String(values["paint-channel"]).to_float()
	if values.has("press"):
		_press = true
	if values.has("walk"):
		_walk_point = _parse_point(String(values["walk"]))
	if values.has("timing"):
		_timing = true
	if values.has("cell"):
		_cell_pixels = String(values["cell"]).to_float()
	if values.has("warp"):
		_warp_point = _parse_point(String(values["warp"]))
	if values.has("uniform"):		# --uniform=vorticity=10,detail_refresh=3 : poked into every simulation
		# pass that declares the parameter, so a solver knob can be A/B tested
		# without rebuilding the room.
		for entry: String in String(values["uniform"]).split(",", false):
			var pair := entry.split("=", false)
			if pair.size() == 2:
				_uniform_overrides[pair[0].strip_edges()] = pair[1].strip_edges().to_float()


func _parse_point(text: String) -> Vector2:
	var parts := text.split(",", false)
	if parts.size() != 2:
		push_warning("gas_diagnostic: expected x,y but got `%s`" % text)
		return Vector2(-9999.0, -9999.0)
	return Vector2(parts[0].strip_edges().to_float(), parts[1].strip_edges().to_float())


## Drives the room's GasBrush for a while along a circle, so the mist is made the
## same way a player makes it (a moving emitter with a real velocity) instead of
## being injected as a one-shot ball.
func _paint() -> void:
	var brush := get_first_node_in_group(&"gas_brush")
	if brush == null:
		push_warning("gas_diagnostic: --paint was given but the room has no GasBrush")
		return
	brush.set("channel", _paint_channel)
	print("gas_diagnostic: painting at %s for %.2f s (radius %.1f)" % [
		str(_paint_center), _paint_seconds, _paint_radius
	])
	var elapsed := 0.0
	while elapsed < _paint_seconds:
		# With `--paint-to` the brush travels in a straight line, which is what a hand
		# does when it swipes the mouse across the room.
		var centre := _paint_center
		if _paint_to.x > -9999.0:
			centre = _paint_center.lerp(_paint_to, clampf(elapsed / _paint_seconds, 0.0, 1.0))
		var angle := elapsed * TAU * 1.5
		var offset := Vector2(cos(angle), sin(angle)) * _paint_radius
		var velocity := Vector2(-sin(angle), cos(angle)) * _paint_radius * TAU * 1.5
		if _paint_to.x > -9999.0 and elapsed > 0.0:
			velocity = (_paint_to - _paint_center) / _paint_seconds
		brush.call("paint_at", centre + offset, velocity)
		await process_frame
		elapsed += 1.0 / maxf(Engine.get_frames_per_second(), 1.0)
	brush.call("stop_painting")
	await process_frame


## Moves the player to a world position and lets the camera follow, which is how the
## capture between two frames shows a *different part of the same gas field*. That is
## the measurement behind "the gas belongs to the world, not to the screen": gas
## painted outside the first frame's view has to turn up in the second frame.
func _walk() -> void:
	var player := get_first_node_in_group(&"player")
	if player == null:
		for child: Node in _all_nodes(_world):
			if child is CharacterBody2D and child.has_method("get_velocity"):
				player = child
				break
	if player == null or not player is Node2D:
		push_warning("gas_diagnostic: --walk was given but no player node was found")
		return
	(player as Node2D).global_position = _walk_point
	var camera := _find_camera(_world) as Camera2D
	if camera != null:
		camera.reset_smoothing()
	print("gas_diagnostic: walked the player to %s" % str(_walk_point))
	for index: int in 20:
		await process_frame


## Moves the OS cursor to a window position and reports the world position the brush
## builds from it, next to the position the camera maths says it should be. This is
## the one part of the painting path a synthetic event cannot fake: everything below
## `get_global_mouse_position()` is Godot's own input routing.
func _check_warp() -> void:
	var brush := get_first_node_in_group(&"gas_brush")
	if brush == null:
		push_warning("gas_diagnostic: --warp was given but the room has no GasBrush")
		return
	Input.warp_mouse(_warp_point)
	await process_frame
	await process_frame
	var actual: Vector2 = brush.call("get_cursor_world")
	var camera := _find_camera(_world)
	var expected := Vector2.INF
	if camera != null:
		expected = (camera as Camera2D).get_screen_center_position() \
			+ (_warp_point / 4.0 - Vector2(_viewport.size) * 0.5)
	print("gas_diagnostic: warp %s -> brush world %s, camera maths %s, delta %s" % [
		str(_warp_point), str(actual), str(expected), str(actual - expected)
	])
	if not _press:
		return
	# Press the left button through the real input path, then read back the brush's
	# state: this is what proves the room can actually be painted with, rather than
	# only through `paint_at()`.
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = _warp_point
	press.global_position = _warp_point
	Input.parse_input_event(press)
	Input.flush_buffered_events()
	await process_frame
	await process_frame
	print("gas_diagnostic: pressed left at %s -> brush painting=%s, world=%s" % [
		str(_warp_point), str(brush.get("_painting")), str(brush.call("get_cursor_world"))
	])
	# Hold long enough for the solver to take a few steps: the emitter is only read
	# once per simulation step, so a two frame press can inject nothing at all.
	for index: int in 40:
		await process_frame
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = _warp_point
	release.global_position = _warp_point
	Input.parse_input_event(release)
	Input.flush_buffered_events()
	print("gas_diagnostic: released -> brush painting=%s" % str(brush.get("_painting")))
	for index: int in 20:
		await process_frame


func _find_camera(node: Node) -> Node:
	if node is Camera2D:
		return node
	for child: Node in node.get_children():
		var found := _find_camera(child)
		if found != null:
			return found
	return null


func _all_nodes(node: Node) -> Array[Node]:
	var result: Array[Node] = [node]
	for child: Node in node.get_children():
		result.append_array(_all_nodes(child))
	return result


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
	for key: String in ["size", "iterations", "passes_per_step", "steps", "ambient", "decay", "refill", "diffusion", "wind", "vorticity", "detail_refresh"]:
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
