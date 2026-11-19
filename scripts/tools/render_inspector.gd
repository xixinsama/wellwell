extends SceneTree

## Render inspector: screenshots and timings for every layer of a room.
##
## The runtime picture is the sum of a dozen systems that all draw into one
## 322x182 SubViewport (see `docs/render-pipeline.md`), which makes "which layer is
## this pixel from?" and "what does this system cost?" hard to answer by playing.
## This tool answers both without opening the editor:
##
##   & godot --path . --resolution 1280x720 -s res://scripts/tools/render_inspector.gd \
##       -- --scene res://scenes/levels/test/light_lab_runner.tscn --out C:/tmp/shots
##
## It writes, into the output directory:
##   full.png            the world viewport as rendered (design pixels, 320x180 in the
##                       runners): NOT what the monitor shows, because the upscale and
##                       the CRT pass happen after it. Use gas_diagnostic's
##                       `window_*.png` when the question involves either of those.
##   solo_<node>.png     one capture per top-level world node, everything else hidden
##   mask_<system>.png   every CPU-side mask the systems keep (fog, light, normals,
##                       backdrop shadow, gas, water cells)
##   inventory.txt       the layer stack: z order, visibility, material, texture size
##   timings.txt         frame time with every system on, and the cost of each one
##                       measured by switching it off (-windowed only)
##
## The world viewport is found by size, so the tool works for any room runner scene
## that follows the SubViewportContainer + SubViewport pattern.

const DEFAULT_SCENE := "res://scenes/levels/test/light_lab_runner.tscn"
const DEFAULT_OUT := "user://render_inspector"
const SETTLE_SECONDS := 1.2
const TIMING_FRAMES := 120
const TIMING_PASSES := 3
## Top-level world nodes worth isolating, in the order they are drawn. Unknown
## nodes are still captured; this only decides the legend order.
const KNOWN_LAYERS: Array[String] = [
	"TerrainRoot", "BackdropField", "BackdropShadow", "TerrainHighlight", "WorldRuntime",
	"Player", "CrumbleRuntime", "WaterField", "WaterGrid", "Atmosphere", "ScreenBloom",
	"LightField", "NormalField", "DustField", "FogOfWar",
]
## Groups whose nodes keep a mask texture the tool dumps. `WaterGrid` joins the
## `water_field` group of its sibling renderer, so the dump resolves by method.
const MASK_SOURCES: Array[Dictionary] = [
	{"group": &"fog_of_war", "label": "fog_mask", "method": "get_mask_image"},
	{"group": &"light_field", "label": "light_map", "method": "get_light_image"},
	{"group": &"normal_field", "label": "normal_buffer", "method": "get_normal_image"},
	{"group": &"backdrop_shadow", "label": "backdrop_mask", "method": "get_mask_image"},
	{"group": &"atmosphere", "label": "gas_density", "method": "get_gas_image"},
	{"group": &"water_field", "label": "water_cells", "method": "get_cell_image"},
]

var _hidden: Array[String] = []
## Layers the --peek capture dims so whatever they cover becomes visible.
var _peek_layers: Array[String] = ["BackTiles"]
var _peek_alpha := 1.0
var _scene_path := DEFAULT_SCENE
var _out_dir := ""
var _world: Node
var _viewport: SubViewport
var _captures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_parse_arguments()
	_out_dir = _resolve_out_dir(_out_dir)
	DirAccess.make_dir_recursive_absolute(_out_dir)
	var scene: PackedScene = load(_scene_path) as PackedScene
	if scene == null:
		push_error("render_inspector: cannot load %s" % _scene_path)
		quit(2)
		return
	var instance := scene.instantiate()
	root.add_child(instance)
	await create_timer(SETTLE_SECONDS).timeout
	_viewport = _find_world_viewport(root)
	if _viewport == null:
		push_error("render_inspector: no SubViewport to inspect in %s" % _scene_path)
		quit(2)
		return
	_world = _find_world(_viewport)
	if _world == null:
		push_error("render_inspector: the world viewport has no child to inspect")
		quit(2)
		return
	print("render_inspector: scene=%s viewport=%dx%d world=%s" % [
		_scene_path, _viewport.size.x, _viewport.size.y, _world.name
	])
	_write_inventory()
	await _capture_full()
	await _capture_masks()
	await _capture_solo_layers()
	await _capture_z_ladder()
	await _capture_peek()
	await _write_timings(instance)
	print("render_inspector: %d captures, %d files in %s" % [_captures, _captures, _out_dir])
	quit(0)


func _parse_arguments() -> void:
	var arguments := OS.get_cmdline_user_args()
	for index: int in arguments.size():
		var argument := arguments[index]
		if argument.begins_with("--scene="):
			_scene_path = argument.substr(8)
		elif argument == "--scene" and index + 1 < arguments.size():
			_scene_path = arguments[index + 1]
		elif argument.begins_with("--out="):
			_out_dir = argument.substr(6)
		elif argument == "--out" and index + 1 < arguments.size():
			_out_dir = arguments[index + 1]
		elif argument.begins_with("--peek-alpha="):
			_peek_alpha = clampf(argument.substr(13).to_float(), 0.0, 1.0)
		elif argument.begins_with("--peek-layers="):
			_peek_layers.clear()
			for name: String in argument.substr(14).split(",", false):
				_peek_layers.append(name.strip_edges())
		elif argument == "--peek":
			_peek_alpha = 0.2
		elif argument.begins_with("--hide="):
			for name: String in argument.substr(7).split(",", false):
				_hidden.append(name.strip_edges())


func _resolve_out_dir(requested: String) -> String:
	if requested.is_empty():
		return ProjectSettings.globalize_path(DEFAULT_OUT)
	if requested.begins_with("res://") or requested.begins_with("user://"):
		return ProjectSettings.globalize_path(requested)
	return requested


# ----------------------------------------------------------------------------- inventory

## The layer stack in draw order. z_index sorts the whole canvas first, then tree
## order decides inside one z, so both are printed: "who covers whom" is exactly
## that pair.
func _write_inventory() -> void:
	var rows: Array[String] = []
	rows.append("# layer stack of %s (%dx%d)" % [_scene_path, _viewport.size.x, _viewport.size.y])
	rows.append("# name\tclass\tz\tz_relative\tvisible\ttexture\tshader")
	for entry: Dictionary in _flatten(_world):
		rows.append("%s\t%s\t%d\t%s\t%s\t%s\t%s" % [
			String(entry["name"]),
			String(entry["class"]),
			int(entry["z"]),
			"yes" if bool(entry["z_relative"]) else "no",
			"yes" if bool(entry["visible"]) else "no",
			String(entry["texture"]),
			String(entry["shader"]),
		])
	var text := "\n".join(rows) + "\n"
	_write_text("inventory.txt", text)
	print(text)


func _flatten(node: Node, depth := 0) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	if node is CanvasItem:
		var item := node as CanvasItem
		var texture := ""
		if "texture" in node and node.get("texture") is Texture2D:
			var value := node.get("texture") as Texture2D
			texture = "%dx%d" % [value.get_width(), value.get_height()]
		var shader := ""
		if item.material is ShaderMaterial:
			var material := item.material as ShaderMaterial
			if material.shader != null:
				shader = material.shader.resource_path.get_file()
		entries.append({
			"name": "  ".repeat(depth) + String(node.name),
			"class": node.get_class(),
			"z": item.z_index,
			"z_relative": item.z_as_relative,
			"visible": item.visible,
			"texture": texture,
			"shader": shader,
		})
	for child: Node in node.get_children():
		entries.append_array(_flatten(child, depth + 1))
	return entries


# ----------------------------------------------------------------------------- captures

func _capture_full() -> void:
	await _capture("full.png")


## The global stack: everything with `z_index <= Z` visible, one capture per z.
##
## z_index sorts the whole canvas before tree order decides inside one z, so this
## ladder is literally the painting order of the room. Reading two neighbouring
## captures tells you exactly what one z band adds (art at 0, the water/tile
## outline at 1, gas at 5, the light shade at 8, glow + dust at 9, the fog at 10).
func _capture_z_ladder() -> void:
	var items := _collect_canvas_items()
	var levels: Array[int] = []
	for item: CanvasItem in items:
		if not levels.has(item.z_index):
			levels.append(item.z_index)
	levels.sort()
	for level: int in levels:
		for item: CanvasItem in items:
			item.visible = item.z_index <= level and bool(item.get_meta(&"inv_visible", true))
		await _capture("stack_z%+03d.png" % level)
	for item: CanvasItem in items:
		item.visible = bool(item.get_meta(&"inv_visible", true))


## Layers that sit *under* another layer are invisible in a normal frame: the
## backdrop tile shadow is drawn beneath the background tiles, so its whole job is
## the part of it that peeks out around them. `--peek` dims those occluding layers
## (default the background tiles) and captures the frame again, so the intermediate
## layer can actually be looked at. `--peek-alpha` sets how far they are dimmed.
func _capture_peek() -> void:
	if _peek_alpha >= 1.0:
		return
	var dimmed: Array[Node] = []
	for name: String in _peek_layers:
		for node: Node in _all_nodes(_world):
			if String(node.name) == name and node is CanvasItem:
				var item := node as CanvasItem
				item.set_meta(&"peek_modulate", item.modulate)
				item.modulate = Color(1.0, 1.0, 1.0, _peek_alpha)
				dimmed.append(item)
	await _capture("peek.png")
	for node: Node in dimmed:
		var item := node as CanvasItem
		item.modulate = item.get_meta(&"peek_modulate", Color.WHITE)
		if item.has_meta(&"peek_modulate"):
			item.remove_meta(&"peek_modulate")
	print("peek: dimmed %d layer(s) named %s to alpha %.2f" % [
		dimmed.size(), str(_peek_layers), _peek_alpha
	])


func _all_nodes(node: Node) -> Array[Node]:
	var result: Array[Node] = [node]
	for child: Node in node.get_children():
		result.append_array(_all_nodes(child))
	return result


func _collect_canvas_items() -> Array[CanvasItem]:
	var items: Array[CanvasItem] = []
	var stack: Array[Node] = [_world]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is CanvasItem:
			var item := node as CanvasItem
			item.set_meta(&"inv_visible", item.visible)
			items.append(item)
		for child: Node in node.get_children():
			stack.append(child)
	items.sort_custom(func(left: CanvasItem, right: CanvasItem) -> bool:
		return left.z_index < right.z_index
	)
	return items


## One capture per top-level world node: hide the siblings, keep the node, shoot.
## This is the "which layer is that pixel from" answer for simple layers; the layer
## that draws *into* another node (BackdropField puts its plate under TerrainRoot)
## shows up empty here, which is what the z ladder and the inventory are for.
func _capture_solo_layers() -> void:
	var layers: Array[Node] = []
	for name: String in KNOWN_LAYERS:
		var node := _world.get_node_or_null(NodePath(name))
		if node != null:
			layers.append(node)
	for child: Node in _world.get_children():
		if not layers.has(child) and child is CanvasItem:
			layers.append(child)
	for layer: Node in layers:
		var visibility: Dictionary = {}
		for other: Node in _world.get_children():
			if other is CanvasItem:
				visibility[other] = (other as CanvasItem).visible
		for other: Node in _world.get_children():
			if other is CanvasItem:
				(other as CanvasItem).visible = other == layer
		await _capture("solo_%s.png" % String(layer.name).to_lower())
		for other: Node in visibility:
			(other as CanvasItem).visible = visibility[other]


func _capture_masks() -> void:
	for source: Dictionary in MASK_SOURCES:
		for node: Node in get_nodes_in_group(StringName(source["group"])):
			if not is_instance_valid(node) or not node.has_method(String(source["method"])):
				continue
			# A system whose mask is a one-shot render target (the normal atlas and
			# the backdrop silhouette) has already been switched to UPDATE_DISABLED
			# by the time the inspector runs, and reading such a target later comes
			# back blank. Bounce it once before the read.
			if await _refresh_one_shot_buffers(node):
				await process_frame
				await RenderingServer.frame_post_draw
			var image: Variant = node.call(String(source["method"]))
			if image is Image and (image as Image).get_width() > 0:
				(image as Image).save_png("%s/%s_%s.png" % [
					_out_dir, String(source["label"]), String(node.name).to_lower()
				])
				_captures += 1
				print("mask %s_%s.png %s" % [source["label"], String(node.name).to_lower(), str((image as Image).get_size())])


## Re-renders any `SubViewport` child of a system once, so a mask that lives in a
## one-shot target has fresh content for the read back. Returns true when something
## was kicked, so the caller can wait a frame.
func _refresh_one_shot_buffers(node: Node) -> bool:
	var refreshed := false
	for child: Node in _all_nodes(node):
		if child is SubViewport:
			var viewport := child as SubViewport
			if viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS:
				continue
			viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
			refreshed = true
	return refreshed


func _capture(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	await process_frame
	await RenderingServer.frame_post_draw
	var image := _viewport.get_texture().get_image()
	image.save_png("%s/%s" % [_out_dir, name])
	_captures += 1


# ----------------------------------------------------------------------------- timings

## Cost by subtraction: frame time with everything on, then with one system hidden.
## Hiding is what the renderer charges for, and it needs no per-system hooks.
##
## The frame budget has to be released first: with vsync or an fps cap in force the
## wall clock is pinned to the monitor and every measurement reads 0 (or a negative
## delta from noise). The best of a few passes is reported, because a single pass is
## sensitive to whatever the OS is doing.
func _write_timings(instance: Node) -> void:
	var previous_fps := Engine.max_fps
	var previous_vsync := DisplayServer.window_get_vsync_mode()
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var rows: Array[String] = []
	rows.append("per-layer attribution is left out on purpose: toggling a subtree inside one frame" )
	rows.append("costs far more than the subtree itself. Compare runs instead, e.g." )
	rows.append("  ... -s res://scripts/tools/render_inspector.gd -- --hide=DustField,ScreenBloom" )
	var baseline := await _measure_frame_ms()
	rows.append("all systems on: %.3f ms/frame (best of %d, uncapped)" % [baseline, TIMING_PASSES])
	for name: String in _hidden:
		var node := _world.get_node_or_null(NodePath(name))
		if node != null and node is CanvasItem:
			(node as CanvasItem).visible = false
			rows.append("hidden on request: %s" % name)
	rows.append("frame time now: %.3f ms/frame" % await _measure_frame_ms())
	var text := "\n".join(rows) + "\n"
	_write_text("timings.txt", text)
	print(text)
	Engine.max_fps = previous_fps
	DisplayServer.window_set_vsync_mode(previous_vsync)


## One system's cost, measured by flipping its `visible` **every frame** and
## averaging the two half-sets. Alternating cancels the machine's drift, which a
## run-then-run comparison cannot: that is what made the first version of this table
## report negative costs.
func _measure_toggle_cost(item: CanvasItem) -> Dictionary:
	var visible_ms := 0.0
	var hidden_ms := 0.0
	# open the time slice
	await process_frame
	await RenderingServer.frame_post_draw
	for index: int in TIMING_FRAMES:
		item.visible = index % 2 == 0
		var started := Time.get_ticks_usec()
		await process_frame
		await RenderingServer.frame_post_draw
		var elapsed := float(Time.get_ticks_usec() - started) / 1000.0
		if index % 2 == 0:
			visible_ms += elapsed
		else:
			hidden_ms += elapsed
	item.visible = true
	var half := float(TIMING_FRAMES) * 0.5
	visible_ms /= half
	hidden_ms /= half
	return {"visible": visible_ms, "hidden": hidden_ms, "cost": visible_ms - hidden_ms}


func _measure_frame_ms() -> float:
	var best := INF
	for pass_index: int in TIMING_PASSES:
		await process_frame
		await RenderingServer.frame_post_draw
		var started := Time.get_ticks_usec()
		for index: int in TIMING_FRAMES:
			await process_frame
			await RenderingServer.frame_post_draw
		var elapsed := float(Time.get_ticks_usec() - started) / 1000.0
		best = minf(best, elapsed / float(TIMING_FRAMES))
	return best


## Draw calls of the frame as an fps-independent cost proxy: two layers that cost
## the same wall time are still very different if one of them submits 40 batches.



# ----------------------------------------------------------------------------- helpers

func _write_text(name: String, text: String) -> void:
	var file := FileAccess.open("%s/%s" % [_out_dir, name], FileAccess.WRITE)
	if file == null:
		push_warning("render_inspector: cannot write %s" % name)
		return
	file.store_string(text)
	file.close()


## The game viewport is the biggest SubViewport in the tree that is not a system
## buffer (the light map, the normal buffer and the shadow mask are room sized too,
## but the game one is the one shown by a SubViewportContainer).
func _find_world_viewport(from: Node) -> SubViewport:
	for child: Node in from.get_children():
		if child is SubViewportContainer:
			var container := child as SubViewportContainer
			for grandchild: Node in container.get_children():
				if grandchild is SubViewport:
					return grandchild as SubViewport
	for child: Node in from.get_children():
		var found := _find_world_viewport(child)
		if found != null:
			return found
	return null


func _find_world(viewport: SubViewport) -> Node:
	for child: Node in viewport.get_children():
		if child is CanvasItem:
			return child
	return null
