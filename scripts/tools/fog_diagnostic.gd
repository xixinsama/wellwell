extends SceneTree

## Fog-of-war diagnostic: dumps the mask the CPU writes, the light map the mask
## samples, and the fog layer exactly as it composites, so the border behaviour can
## be measured instead of argued about.
##
##   & godot --path . --resolution 1280x720 -s res://scripts/tools/fog_diagnostic.gd \
##       -- --room test_fog_start --out C:/tmp/fog --settle 2.0 --frames 3 --interval 0.4
##
## Per frame it writes:
##   full_%02d.png    the world viewport as the game shows it (design pixels)
##   fog_%02d.png     the FogOfWar layer alone over a transparent background
##   mask_%02d.png    the RGBA8 mask (a = fog opacity, r = flash, g = border distance)
##   light_%02d.png   the room light map the mask's light push samples
## and once `info.txt` with the geometry both of them are addressed in: the mask's
## origin and size in world pixels, the light map's size and room origin, the cell
## size and the player position. Those numbers are what a coordinate bug hides in.
##
## `--uniform=key=value` pokes a shader parameter on every material under the world
## (for this shader: `light_push_px`, `tendril_pixels`, `edge_softness`,
## `debug_view`, ...). Two captures with and without a term are the honest way to
## see what that term does.
##
## `--at=x,y` teleports the player once (world pixels) and lets the room reveal
## itself again, so a boundary can be approached deliberately; `--step=dx,dy` moves
## it every frame instead, which is what shows a *sweep* (the reveal wave).
##
## `--stage=x,y` stages the player for N seconds before the captures start
## (`--stage-seconds`), so the reveal wave has finished and the border is settled.

const DEFAULT_SCENE := "res://scenes/levels/test_world/runners/test_world_runner.tscn"
const DEFAULT_OUT := "user://fog_diagnostic"

var _scene_path := DEFAULT_SCENE
var _out_dir := ""
var _room := ""
var _settle := 2.0
var _frames := 1
var _interval := 0.4
var _uniform_overrides: Dictionary = {}
var _at := Vector2(-99999.0, -99999.0)
var _step := Vector2.ZERO
var _stage := Vector2(-99999.0, -99999.0)
var _stage_seconds := 1.2
var _world: Node
var _viewport: SubViewport
var _fog: Node
var _light: Node
var _player: Node2D


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_parse_arguments()
	_out_dir = _resolve_out_dir(_out_dir)
	DirAccess.make_dir_recursive_absolute(_out_dir)
	var scene: PackedScene = load(_scene_path) as PackedScene
	if scene == null:
		push_error("fog_diagnostic: cannot load %s" % _scene_path)
		quit(2)
		return
	var instance := scene.instantiate()
	# The room override has to be on the runner before it enters the tree, because
	# the world starts in `_ready`.
	if not _room.is_empty() and "start_room_override" in instance:
		instance.set("start_room_override", _room)
	root.add_child(instance)
	await create_timer(_settle).timeout
	_viewport = _find_world_viewport(root)
	_world = _find_world(_viewport)
	_fog = get_first_node_in_group(&"fog_of_war")
	_light = get_first_node_in_group(&"light_field")
	_player = _find_player(_world)
	if _viewport == null or _world == null or _fog == null:
		push_error("fog_diagnostic: no viewport/world/fog in %s (room `%s`)" % [_scene_path, _room])
		quit(2)
		return
	# The game viewport is opaque, so a solo capture would read alpha = 1 everywhere.
	_viewport.transparent_bg = true
	print("fog_diagnostic: viewport=%dx%d fog=%s room=%s" % [
		_viewport.size.x, _viewport.size.y, String(_fog.name), _room if not _room.is_empty() else "<world start>"
	])
	if _stage.x > -99999.0:
		await _teleport(_stage, _stage_seconds)
	if _at.x > -99999.0:
		await _teleport(_at, 0.35)
	_apply_uniform_overrides()
	_write_info()
	_dump_light()
	for index: int in _frames:
		await _capture_frame(index)
		if _step != Vector2.ZERO and _player != null:
			_player.global_position += _step
			if _fog.has_method("reveal_from_player"):
				_fog.call("reveal_from_player")
		if index + 1 < _frames:
			await create_timer(_interval).timeout
	print("fog_diagnostic: wrote %d frame(s) to %s" % [_frames, _out_dir])
	quit(0)


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
	if values.has("room"):
		_room = String(values["room"])
	if values.has("settle"):
		_settle = String(values["settle"]).to_float()
	if values.has("frames"):
		_frames = maxi(String(values["frames"]).to_int(), 1)
	if values.has("interval"):
		_interval = maxf(String(values["interval"]).to_float(), 0.0)
	if values.has("at"):
		_at = _parse_point(String(values["at"]))
	if values.has("step"):
		_step = _parse_point(String(values["step"]))
	if values.has("stage"):
		_stage = _parse_point(String(values["stage"]))
	if values.has("stage-seconds"):
		_stage_seconds = maxf(String(values["stage-seconds"]).to_float(), 0.0)
	if values.has("uniform"):
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


func _parse_point(text: String) -> Vector2:
	var parts := text.split(",", false)
	if parts.size() != 2:
		push_warning("fog_diagnostic: expected x,y but got `%s`" % text)
		return Vector2(-99999.0, -99999.0)
	return Vector2(parts[0].strip_edges().to_float(), parts[1].strip_edges().to_float())


func _teleport(world_position: Vector2, seconds: float) -> void:
	if _player == null:
		push_warning("fog_diagnostic: no player to move")
		return
	_player.global_position = world_position
	if _fog.has_method("reveal_from_player"):
		_fog.call("reveal_from_player")
	print("fog_diagnostic: player -> %s (world), waiting %.2f s" % [str(world_position), seconds])
	await create_timer(seconds).timeout


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
	print("fog_diagnostic: uniform overrides %s -> %s" % [str(_uniform_overrides), str(applied)])


func _shader_materials(node: Node) -> Array[ShaderMaterial]:
	var result: Array[ShaderMaterial] = []
	for child: Node in node.get_children():
		if child is CanvasItem:
			var material := (child as CanvasItem).material
			if material is ShaderMaterial and (material as ShaderMaterial).shader != null:
				result.append(material as ShaderMaterial)
		result.append_array(_shader_materials(child))
	return result


func _capture_frame(index: int) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	await process_frame
	await RenderingServer.frame_post_draw
	_viewport.get_texture().get_image().save_png("%s/full_%02d.png" % [_out_dir, index])
	var solo := await _capture_with_only(_fog)
	if solo != null:
		solo.save_png("%s/fog_%02d.png" % [_out_dir, index])
		print("frame %02d: fog lit %.1f%%, mean alpha %.4f, player %s" % [
			index,
			_lit_share(solo) * 100.0,
			_mean_alpha(solo),
			str(_player.global_position if _player != null else Vector2.ZERO),
		])
	var mask: Variant = _fog.call("get_mask_image")
	if mask is Image and (mask as Image).get_width() > 0:
		(mask as Image).save_png("%s/mask_%02d.png" % [_out_dir, index])


func _capture_with_only(keep: Node) -> Image:
	var visibility: Dictionary = {}
	for child: Node in _world.get_children():
		if child is CanvasItem:
			var item := child as CanvasItem
			visibility[item] = item.visible
			item.visible = item == keep
	await process_frame
	await RenderingServer.frame_post_draw
	await process_frame
	await RenderingServer.frame_post_draw
	var image := _viewport.get_texture().get_image()
	for item: CanvasItem in visibility:
		item.visible = visibility[item]
	return image


func _lit_share(image: Image) -> float:
	var lit := 0
	var total := image.get_width() * image.get_height()
	for y: int in image.get_height():
		for x: int in image.get_width():
			if image.get_pixel(x, y).a > 0.02:
				lit += 1
	return float(lit) / float(maxi(total, 1))


func _mean_alpha(image: Image) -> float:
	var total := 0.0
	for y: int in image.get_height():
		for x: int in image.get_width():
			total += image.get_pixel(x, y).a
	return total / float(maxi(image.get_width() * image.get_height(), 1))


func _dump_light() -> void:
	if _light != null and _light.has_method("get_light_image"):
		var image: Variant = _light.call("get_light_image")
		if image is Image and (image as Image).get_width() > 0:
			(image as Image).save_png("%s/light_map.png" % _out_dir)


func _write_info() -> void:
	var rows: Array[String] = []
	rows.append("# fog diagnostic of %s (room `%s`)" % [_scene_path, _room])
	rows.append("viewport\t%d x %d" % [_viewport.size.x, _viewport.size.y])
	rows.append("mask_origin\t%s" % str(_fog.call("get_mask_origin_pixels")))
	rows.append("mask_size\t%s" % str(_fog.call("get_mask_size_pixels")))
	rows.append("cell_size\t%s" % str(_fog.get("cell_size")))
	rows.append("map_origin_cell\t%s" % str(_fog.get("map_origin_cell")))
	rows.append("map_size_cells\t%s" % str(_fog.get("map_size_cells")))
	rows.append("chunk_size_pixels\t%s" % str(_fog.get("chunk_size_pixels")))
	if _light != null:
		rows.append("light_pixels\t%s" % str(_light.call("get_light_pixels")))
		rows.append("light_room_origin\t%s" % str(_light.get("_room_origin_pixels")))
	rows.append("player\t%s" % str(_player.global_position if _player != null else Vector2.ZERO))
	for property: String in [
		"tendril_pixels", "edge_softness", "edge_noise_scale", "edge_noise_grain",
		"edge_noise_speed", "edge_noise_warp", "breath_pixels", "breath_scale",
		"dither_strength", "dither_scale", "light_push_px", "light_gain",
		"focus_radius_px", "focus_falloff_px",
	]:
		rows.append("%s\t%s" % [property, str(_fog.get(property))])
	_write_text("info.txt", "\n".join(rows) + "\n")
	print("\n".join(rows))


func _write_text(name: String, text: String) -> void:
	var file := FileAccess.open("%s/%s" % [_out_dir, name], FileAccess.WRITE)
	if file == null:
		push_warning("fog_diagnostic: cannot write %s" % name)
		return
	file.store_string(text)
	file.close()


func _find_player(node: Node) -> Node2D:
	if node is CharacterBody2D and node.has_method("get") and "velocity" in node:
		return node as Node2D
	for child: Node in node.get_children():
		var found := _find_player(child)
		if found != null:
			return found
	return null


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
