class_name FogOfWar
extends Node2D

## Room fog with authored light and dark zones.
##
## Reveal model: the inside of the current camera view is revealed at once by an
## eight-direction flood fill (diagonal cracks are see-through by design). Solid
## tiles block the fill; glass, one-way platforms (unless the setting enables
## their downward occlusion) and decorations do not. Cells stay revealed for the
## rest of the room visit and are persisted per room.
##
## Three things stay black:
## - cells outside the camera view (multi-chunk rooms are revealed screen by screen)
## - sealed pockets the sight fill cannot reach
## - authored dark zones (until their reveal condition fires)
##
## Authored light zones are always lit, even inside a sealed pocket.
##
## Rendering: the fog is a single GPU quad over the room, not one draw_rect per
## cell. The CPU writes a mask texture with one texel block per cell (alpha =
## fog opacity, red = reveal flash) and FogMask turns that into an animated
## border: a blurred presence band whose cut is pushed around by layered noise,
## so the shadow grows tendrils and slowly breathes instead of following the
## cell grid. The mask is only rewritten when the revealed set, a reveal wave or
## the focus spotlight actually changes, so a settled room costs nothing.

const FOG_VISIBILITY: Script = preload("res://addons/metroidvania_kit/map/discovery/fog_visibility.gd")
const ROOM_DATA_SCRIPT: Script = preload("res://addons/platformer_kit/world/data/room_data.gd")
const FOG_SHADER: Shader = preload("res://addons/metroidvania_kit/map/discovery/fog_mask.gdshader")
const ZONE_GROUP := &"fog_zone"
const OCCLUDER_GROUP := &"fog_occluder"
const FOG_GROUP := &"fog_of_war"
## How far the mask's distance channel reaches, in pixels. Encoded as
## 0.5 + distance / (2 * MASK_DISTANCE_PIXELS); the shader must use the same
## value, so it is pushed as a uniform.
const MASK_DISTANCE_PIXELS := 32.0


@export var player_path: NodePath
@export var terrain_path: NodePath
@export var map_origin_cell := Vector2i(-24, -12)
@export var map_size_cells := Vector2i(80, 32)
@export var cell_size := Vector2i(8, 8)
@export var chunk_size_pixels := Vector2i(320, 180)
@export var level_id := "level_01"
@export var fog_color := Color.BLACK:
	set(value):
		fog_color = value
		_apply_mask_shader_parameters()
@export var glass_tile_atlas := Vector2i(0, 3)
@export var reveal_seconds := 0.28
@export var reveal_stagger_seconds := 0.012
@export var reveal_flash_seconds := 0.12
## The hero volume used for zone membership, relative to the player origin
## (feet). The sprite is 10x10 and the feet origin is at its bottom edge.
@export var hero_body_rect := Rect2(-5, -10, 10, 10)

@export_group("Fog Edge")
## How far the noise may push the border out or in, in pixels. This is also the
## depth of the tendrils that grow out of (and bite into) the shadow.
@export_range(0.0, 20.0, 0.5) var tendril_pixels := 7.0
## Anti-alias width of the cut in pixels; 0 gives a hard pixel edge.
@export_range(0.0, 8.0, 0.1) var edge_softness := 1.6
## Size of the coarse lobes in pixels; smaller means busier tendrils.
@export_range(2.0, 60.0, 0.5) var edge_noise_scale := 13.0
## Size of the fine grain layer in pixels.
@export_range(1.0, 16.0, 0.1) var edge_noise_grain := 3.2
## Drift speed of the lobes; 0 freezes the border.
@export_range(0.0, 3.0, 0.05) var edge_noise_speed := 0.55
## How strongly the lobes are bent, which turns blobs into tongues.
@export_range(0.0, 2.0, 0.05) var edge_noise_warp := 0.65

@export_group("Fog Breathing")
## How far the whole border swells in and out, in pixels. This is the shadow
## slowly inhaling rather than only shimmering where the noise is.
@export_range(0.0, 16.0, 0.5) var breath_pixels := 3.0
## Size of the swell lobes in pixels; big values move the whole silhouette.
@export_range(8.0, 160.0, 1.0) var breath_scale := 46.0
## Speed of the swell.
@export_range(0.0, 2.0, 0.01) var breath_speed := 0.16

@export_group("Fog Pixel Grain")
## Blend towards a 4x4 ordered dither on the border, 0 (smooth) to 1 (chunky).
@export_range(0.0, 1.0, 0.01) var dither_strength := 0.6
## Size of one dither cell in pixels; 1 keeps the grain at design resolution.
@export_range(1.0, 4.0, 1.0) var dither_scale := 1.0

var currently_visible: Dictionary[Vector2i, bool] = {}

var _explored_cells: Dictionary[Vector2i, bool] = {}
var _dark_cells: Dictionary[Vector2i, bool] = {}
var _light_cells: Dictionary[Vector2i, bool] = {}
var _revealed_zones: Dictionary[String, bool] = {}
var _ripple: Dictionary[Vector2i, float] = {}
var _mask_image: Image
var _mask_texture: ImageTexture
## Binary revealed/fogged field the animated mask is rebuilt from.
var _mask_base: Image
var _mask_base_dirty := true
var _mask_sprite: Sprite2D
var _mask_material: ShaderMaterial
var _player: Node2D
var _terrain: Node
var _solid_tiles: TileMapLayer
var _persistence_source: Object
var _persistence_source_is_bound := false
var _settings_source: Object
var _warned_missing_player := false
var _player_is_explicitly_bound := false
var _room_binding_is_explicit := false
var _room_is_bound := false
var _has_exact_room_bounds := false
var _room_origin_pixels := Vector2i.ZERO
var _room_size_pixels := Vector2i.ZERO
var _last_origin_cell := Vector2i(2147483647, 2147483647)
var _last_view_bounds := Rect2i()
var _last_zone_signature := ""
var _dirty := true
var _blockers: Dictionary[Vector2i, bool] = {}
var _one_way_cells: Dictionary[Vector2i, bool] = {}
var _blockers_dirty := true
var _exploration_version := 0
var _focus_zone: Node
var _focus_cells: Dictionary[Vector2i, bool] = {}
var _focus_light_cells: Dictionary[Vector2i, bool] = {}
var _focus_center := Vector2i.ZERO
var _focus_max_distance := 1.0
var _focus_start := 0.0
var _focus_release := -1.0
var _focus_seconds := 0.35
var _focus_alpha := 0.92


func _ready() -> void:
	add_to_group(FOG_GROUP)
	if not _player_is_explicitly_bound and player_path != NodePath():
		_player = get_node_or_null(player_path) as Node2D
	_resolve_terrain()
	_load_saved_progress()
	_apply_saved_zones()
	reveal_from_player()


func _process(_delta: float) -> void:
	if not _is_fog_enabled():
		return
	if _room_binding_is_explicit and not _room_is_bound:
		return
	var now := _now()
	_settle_finished_focus(now)
	var origin := _current_player_cell()
	var view := _view_bounds_cells()
	var zone_signature := _zone_overlap_signature()
	if origin != _last_origin_cell or view != _last_view_bounds or zone_signature != _last_zone_signature or _dirty:
		reveal_from_player()
	elif _mask_animating(now):
		_update_mask_image(now)


## The shader animates on its own; the mask only has to be repainted while a
## reveal wave is still evaporating or the focus spotlight is still fading in
## or out. A settled room repaints nothing at all.
func _mask_animating(now: float) -> bool:
	if not _ripple.is_empty():
		return true
	if _focus_zone != null and now - _focus_start < _focus_seconds:
		return true
	if _focus_release >= 0.0 and now - _focus_release < _focus_seconds:
		return true
	return false


func _settle_finished_focus(now: float) -> void:
	if _focus_release < 0.0 or now - _focus_release < _focus_seconds:
		return
	_clear_focus()
	_update_mask_image(now)


func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0


func world_to_cell(world_position: Vector2) -> Vector2i:
	if _has_exact_room_bounds:
		var local_position := world_position - Vector2(_room_origin_pixels)
		return map_origin_cell + Vector2i(
			floori(local_position.x / float(cell_size.x)),
			floori(local_position.y / float(cell_size.y))
		)
	return Vector2i(
		floori(world_position.x / float(cell_size.x)),
		floori(world_position.y / float(cell_size.y))
	)


func cell_to_id(cell: Vector2i) -> String:
	return "%s:%d,%d" % [level_id, cell.x, cell.y]


func load_explored_cells(cell_ids: Array[String]) -> void:
	var added := false
	for cell_id: String in cell_ids:
		var parsed: Variant = _id_to_cell(cell_id)
		if parsed != null and not _explored_cells.has(parsed):
			_explored_cells[parsed] = true
			added = true
	if added:
		_exploration_version += 1
		_mask_base_dirty = true
	queue_redraw()


func replace_explored_cells(cell_ids: Array[String]) -> void:
	_explored_cells.clear()
	load_explored_cells(cell_ids)
	_update_mask_image()


func replace_revealed_zones(zone_ids: Array[String]) -> void:
	_revealed_zones.clear()
	for zone_id: String in zone_ids:
		if not zone_id.is_empty():
			_revealed_zones[zone_id] = true
	_apply_saved_zones()
	_dirty = true
	queue_redraw()


func get_revealed_zones() -> Array[String]:
	var result: Array[String] = []
	result.assign(_revealed_zones.keys())
	result.sort()
	return result


func is_cell_explored(cell: Vector2i) -> bool:
	return _explored_cells.has(cell)


## Live exploration of the loaded room, as stable "room:x,y" ids. The persistence
## bridge owns the union of every visited room; this covers the current room when
## no bridge is bound (for example in a preview or a test world run).
func get_explored_cell_ids() -> Array[String]:
	var result: Array[String] = []
	for cell: Vector2i in _explored_cells:
		result.append(cell_to_id(cell))
	result.sort()
	return result


func get_exploration_version() -> int:
	return _exploration_version


func is_cell_lit(cell: Vector2i) -> bool:
	if _light_cells.has(cell):
		return true
	if _dark_cells.has(cell):
		return false
	return _explored_cells.has(cell)


func is_focus_active() -> bool:
	return _focus_zone != null


## The raw mask the fog shader reads: alpha is the fog opacity of a cell, red
## is its reveal flash. Cells are still 0 or 1 once a reveal wave has finished,
## but mid-wave and under the focus spotlight they hold in-between values.
func get_mask_image() -> Image:
	return _mask_image


func get_mask_texture() -> ImageTexture:
	return _mask_texture


func get_mask_origin_pixels() -> Vector2i:
	return _room_origin_pixels if _has_exact_room_bounds else Vector2i(
		map_origin_cell.x * cell_size.x,
		map_origin_cell.y * cell_size.y
	)


func get_mask_size_pixels() -> Vector2i:
	if _has_exact_room_bounds:
		return _room_size_pixels
	return Vector2i(map_size_cells.x * cell_size.x, map_size_cells.y * cell_size.y)


func bind_player(player: Node2D) -> void:
	_player_is_explicitly_bound = true
	_player = player
	_warned_missing_player = false
	_dirty = true


func bind_room(room_data: RoomData, terrain_root: Node, origin_chunk: Variant = null) -> bool:
	if not _is_room_data(room_data) or terrain_root == null:
		return false
	var terrain := terrain_root.get_node_or_null("Terrain")
	if terrain == null:
		return false

	clear_room()
	_room_binding_is_explicit = true
	_room_is_bound = true
	level_id = room_data.room_id
	_terrain = terrain
	_solid_tiles = terrain.get_node_or_null("SolidTiles") as TileMapLayer
	_blockers_dirty = true
	var effective_origin := Vector2i.ZERO if origin_chunk == null else Vector2i(origin_chunk)
	set_room_chunks(effective_origin, room_data.room_size_chunks)
	_load_saved_progress()
	_apply_saved_zones()
	_dirty = true
	reveal_from_player()
	return true


func bind_room_with_origin(room_data: RoomData, terrain_root: Node, origin_chunk: Vector2i) -> bool:
	return bind_room(room_data, terrain_root, origin_chunk)


func clear_room() -> void:
	_room_binding_is_explicit = true
	_room_is_bound = false
	_has_exact_room_bounds = false
	_room_origin_pixels = Vector2i.ZERO
	_room_size_pixels = Vector2i.ZERO
	_terrain = null
	_solid_tiles = null
	currently_visible.clear()
	_explored_cells.clear()
	_dark_cells.clear()
	_light_cells.clear()
	_revealed_zones.clear()
	_ripple.clear()
	_clear_focus()
	_release_mask()
	_last_origin_cell = Vector2i(2147483647, 2147483647)
	_last_view_bounds = Rect2i()
	_last_zone_signature = ""
	_exploration_version += 1
	_dirty = true
	_blockers_dirty = true
	queue_redraw()


func bind_persistence_source(source: Object) -> void:
	_persistence_source = source
	_persistence_source_is_bound = true


func clear_persistence_source() -> void:
	_persistence_source = null
	_persistence_source_is_bound = true


func bind_settings_source(source: Object) -> void:
	_settings_source = source


func set_room_chunks(room_origin_chunk: Vector2i, room_size_chunks: Vector2i) -> void:
	var cells_per_chunk := _cells_per_chunk()
	map_origin_cell = Vector2i(
		room_origin_chunk.x * cells_per_chunk.x,
		room_origin_chunk.y * cells_per_chunk.y
	)
	_room_origin_pixels = room_origin_chunk * chunk_size_pixels
	_room_size_pixels = room_size_chunks * chunk_size_pixels
	map_size_cells = Vector2i(
		ceili(float(_room_size_pixels.x) / float(cell_size.x)),
		ceili(float(_room_size_pixels.y) / float(cell_size.y))
	)
	_has_exact_room_bounds = true
	_release_mask()
	_last_view_bounds = Rect2i()
	_explored_cells.clear()
	_ripple.clear()
	_clear_focus()
	_dirty = true
	queue_redraw()


## Called by fog zones, doors and the crumble runtime when the world changes.
func request_refresh() -> void:
	_dirty = true
	_blockers_dirty = true
	_mask_base_dirty = true


func reveal_from_player() -> void:
	if _room_binding_is_explicit and not _room_is_bound:
		visible = false
		return
	if not _is_fog_enabled():
		visible = false
		return
	visible = true

	if not _player_is_explicitly_bound and _player == null and player_path != NodePath():
		_player = get_node_or_null(player_path) as Node2D
	if _player == null:
		if not _player_is_explicitly_bound:
			_warn_once_missing_player()
		queue_redraw()
		return

	var origin := world_to_cell(_player.global_position)
	var bounds := _view_bounds_cells()
	_dirty = false
	_last_origin_cell = origin
	_last_view_bounds = bounds
	_last_zone_signature = _zone_overlap_signature()
	var one_way: Dictionary = _one_way_cells if _is_one_way_occlusion_enabled() else {}
	_reveal(origin, bounds, _collect_sight(), one_way)


func reveal_from_cell(origin: Vector2i, blockers: Dictionary, bounds: Rect2i = Rect2i()) -> void:
	_reveal(origin, bounds, blockers, {})


func _reveal(origin: Vector2i, bounds: Rect2i, blockers: Dictionary, one_way: Dictionary) -> void:
	var effective_bounds := bounds
	if effective_bounds.size == Vector2i.ZERO:
		effective_bounds = _room_cell_rect()
	var visibility: RefCounted = FOG_VISIBILITY.new()
	var visible_cells: Dictionary[Vector2i, bool] = visibility.compute_visible_cells(
		origin,
		effective_bounds,
		blockers,
		one_way
	)
	_collect_zone_cells()
	for cell: Vector2i in _light_cells:
		visible_cells[cell] = true
	for cell: Vector2i in _dark_cells:
		visible_cells.erase(cell)
	currently_visible = visible_cells

	var now := _now()
	var save_manager := _get_persistence_source()
	var distance_scale := float(cell_size.x)
	for cell: Vector2i in visible_cells.keys():
		if not _is_inside_map(cell) or _explored_cells.has(cell):
			continue
		_explored_cells[cell] = true
		_exploration_version += 1
		var distance := Vector2(cell - origin).length() / distance_scale
		_ripple[cell] = now + distance * reveal_stagger_seconds
		if save_manager != null and save_manager.has_method("mark_cell_explored"):
			save_manager.call("mark_cell_explored", cell_to_id(cell))
	_mask_base_dirty = true
	_update_mask_image()


func _draw() -> void:
	# The fog is the FogMask quad now; nothing is drawn immediate mode, so a
	# repaint can never leave a stale per-cell rect behind.
	pass


## Per-cell fog opacity of a reveal wave, 0 when the wave is done here.
func _ripple_alpha(cell: Vector2i, now: float) -> float:
	if not _ripple.has(cell):
		return -1.0
	var start: float = _ripple[cell]
	var elapsed := now - start
	if elapsed < 0.0:
		return 1.0
	if elapsed >= reveal_seconds:
		return 0.0
	return clampf(1.0 - elapsed / maxf(reveal_seconds, 0.001), 0.0, 1.0)


func _ripple_flash(cell: Vector2i, now: float) -> float:
	if not _ripple.has(cell) or reveal_flash_seconds <= 0.0:
		return 0.0
	var elapsed := now - float(_ripple[cell])
	if elapsed < 0.0 or elapsed >= reveal_flash_seconds:
		return 0.0
	return clampf(1.0 - elapsed / reveal_flash_seconds, 0.0, 1.0)


## Extra darkness the focus spotlight adds on top of an already lit cell.
func _focus_alpha_at(cell: Vector2i, now: float) -> float:
	if _focus_cells.is_empty() and _focus_zone == null:
		return 0.0
	if _focus_cells.has(cell) or not is_cell_lit(cell):
		return 0.0
	var strength := _focus_strength(now)
	if strength <= 0.0:
		return 0.0
	var distance := Vector2(cell - _focus_center).length()
	var far := 1.0 - clampf(distance / maxf(_focus_max_distance, 1.0), 0.0, 1.0)
	var local := clampf((strength - far * 0.55) / 0.45, 0.0, 1.0)
	if local <= 0.0:
		return 0.0
	return local * _focus_alpha


func _focus_strength(now: float) -> float:
	if _focus_zone != null:
		return clampf((now - _focus_start) / maxf(_focus_seconds, 0.01), 0.0, 1.0)
	if _focus_release < 0.0:
		return 0.0
	return clampf(1.0 - (now - _focus_release) / maxf(_focus_seconds, 0.01), 0.0, 1.0)


func _start_focus(zone: Node, cells: Dictionary[Vector2i, bool], seconds: float, alpha: float) -> void:
	if _focus_zone == zone:
		return
	_focus_zone = zone
	_focus_cells = cells
	_focus_center = _current_player_cell() if is_instance_valid(_player) else _cells_center(cells)
	_focus_max_distance = _max_cell_distance(_focus_center, cells)
	_focus_start = _now()
	_focus_release = -1.0
	_focus_seconds = maxf(seconds, 0.01)
	_focus_alpha = clampf(alpha, 0.0, 1.0)
	queue_redraw()


func _release_focus() -> void:
	if _focus_zone == null:
		return
	_focus_zone = null
	_focus_release = _now()
	queue_redraw()


func _clear_focus() -> void:
	_focus_zone = null
	_focus_cells.clear()
	_focus_center = Vector2i.ZERO
	_focus_max_distance = 1.0
	_focus_release = -1.0


func _cells_center(cells: Dictionary[Vector2i, bool]) -> Vector2i:
	if cells.is_empty():
		return Vector2i.ZERO
	var sum := Vector2i.ZERO
	for cell: Vector2i in cells:
		sum += cell
	return Vector2i(sum.x / cells.size(), sum.y / cells.size())


func _max_cell_distance(center: Vector2i, cells: Dictionary[Vector2i, bool]) -> float:
	var maximum := 1.0
	for cell: Vector2i in cells:
		maximum = maxf(maximum, Vector2(cell - center).length())
	return maximum


func _load_saved_progress() -> void:
	var save_manager := _get_persistence_source()
	if save_manager == null:
		return
	if save_manager.has_method("get_explored_cells"):
		var ids: Array[String] = []
		ids.assign(save_manager.call("get_explored_cells"))
		load_explored_cells(ids)
	if save_manager.has_method("get_revealed_zones"):
		var zone_ids: Array[String] = []
		zone_ids.assign(save_manager.call("get_revealed_zones"))
		for zone_id: String in zone_ids:
			if zone_id.begins_with("%s:" % level_id):
				_revealed_zones[zone_id] = true


func _apply_saved_zones() -> void:
	if not is_inside_tree():
		return
	for node: Node in get_tree().get_nodes_in_group(ZONE_GROUP):
		if not is_instance_valid(node) or not node.has_method("get_zone_key"):
			continue
		var key := String(node.call("get_zone_key", level_id))
		if not _revealed_zones.has(key):
			continue
		if node.has_method("set_seen"):
			node.call("set_seen", true)
		var restore := bool(node.get("restore_on_exit")) if "restore_on_exit" in node else false
		if not restore and node.has_method("set_revealed"):
			node.call("set_revealed", true)


func _collect_zone_cells() -> void:
	_dark_cells.clear()
	_light_cells.clear()
	if not is_inside_tree():
		return
	var room := _room_cell_rect()
	var player_position := _player.global_position if is_instance_valid(_player) else Vector2.INF
	var now := _now()
	var save_manager := _get_persistence_source()
	var active_focus: Node = null
	var active_focus_cells: Dictionary[Vector2i, bool] = {}
	var active_focus_seconds := 0.35
	var active_focus_alpha := 0.92
	for node: Node in get_tree().get_nodes_in_group(ZONE_GROUP):
		if not is_instance_valid(node) or not node.has_method("get_world_rect"):
			continue
		var zone_rect: Rect2 = node.call("get_world_rect")
		if not zone_rect.intersects(Rect2(_room_origin_pixels, Vector2(_room_size_pixels))):
			continue
		var zone_cells := _cells_in_world_rect(zone_rect, room)
		if zone_cells.is_empty():
			continue
		var is_light := bool(node.call("is_light"))
		if is_light:
			for cell: Vector2i in zone_cells:
				_light_cells[cell] = true
			continue
		var hero_rect := _hero_world_rect(player_position)
		var overlaps := zone_rect.intersects(hero_rect)
		var fully_inside := zone_rect.encloses(hero_rect)
		var reveal_on_enter := bool(node.get("reveal_on_enter")) if "reveal_on_enter" in node else false
		var restore_on_exit := bool(node.get("restore_on_exit")) if "restore_on_exit" in node else false
		var revealed := bool(node.get("revealed")) if "revealed" in node else false
		if reveal_on_enter and overlaps and not revealed:
			revealed = true
			if node.has_method("set_revealed"):
				node.call("set_revealed", true)
			if node.has_method("set_seen"):
				node.call("set_seen", true)
			var key := String(node.call("get_zone_key", level_id))
			_revealed_zones[key] = true
			if save_manager != null and save_manager.has_method("mark_zone_revealed"):
				save_manager.call("mark_zone_revealed", key)
		elif restore_on_exit and not overlaps and revealed:
			revealed = false
			if node.has_method("set_revealed"):
				node.call("set_revealed", false)
		if not revealed:
			for cell: Vector2i in zone_cells:
				_dark_cells[cell] = true
			continue
		for cell: Vector2i in zone_cells:
			if _explored_cells.has(cell):
				continue
			_explored_cells[cell] = true
			_exploration_version += 1
			_ripple[cell] = now
			if save_manager != null and save_manager.has_method("mark_cell_explored"):
				save_manager.call("mark_cell_explored", cell_to_id(cell))
		if "focus_room" in node and bool(node.get("focus_room")) and fully_inside:
			active_focus = node
			active_focus_cells = zone_cells
			if "focus_seconds" in node:
				active_focus_seconds = float(node.get("focus_seconds"))
			if "focus_alpha" in node:
				active_focus_alpha = float(node.get("focus_alpha"))
	if active_focus != null:
		_start_focus(active_focus, active_focus_cells, active_focus_seconds, active_focus_alpha)
	else:
		_release_focus()


func _cells_in_world_rect(world_rect: Rect2, bounds: Rect2i) -> Dictionary[Vector2i, bool]:
	var result: Dictionary[Vector2i, bool] = {}
	if world_rect.size.x <= 0.0 or world_rect.size.y <= 0.0:
		return result
	var start := world_to_cell(world_rect.position)
	var end := world_to_cell(world_rect.end - Vector2(0.001, 0.001))
	for y: int in range(start.y, end.y + 1):
		for x: int in range(start.x, end.x + 1):
			var cell := Vector2i(x, y)
			if bounds.has_point(cell):
				result[cell] = true
	return result


func _collect_sight() -> Dictionary[Vector2i, bool]:
	if not _blockers_dirty:
		return _blockers
	_blockers.clear()
	_one_way_cells.clear()
	_blockers_dirty = false
	_resolve_terrain()
	if _solid_tiles != null:
		_add_solid_layer(_solid_tiles)
	_add_legacy_layers()
	_add_occluder_blockers()
	return _blockers


func _add_solid_layer(layer: TileMapLayer) -> void:
	for tile_cell: Vector2i in layer.get_used_cells():
		var atlas := layer.get_cell_atlas_coords(tile_cell)
		if atlas == glass_tile_atlas:
			continue
		var tile_data := layer.get_cell_tile_data(tile_cell)
		if tile_data == null:
			continue
		var has_solid := false
		var has_one_way := false
		var physics_layers := 1
		if layer.tile_set != null:
			physics_layers = layer.tile_set.get_physics_layers_count()
		for physics_layer: int in physics_layers:
			for index in tile_data.get_collision_polygons_count(physics_layer):
				if tile_data.is_collision_polygon_one_way(physics_layer, index):
					has_one_way = true
				else:
					has_solid = true
		if not has_solid and not has_one_way:
			continue
		var cell := world_to_cell(layer.to_global(layer.map_to_local(tile_cell)))
		if has_solid:
			_blockers[cell] = true
		else:
			_one_way_cells[cell] = true


## Old rooms still split glass/crumble/vision into their own layers; keep them
## working without requiring a re-bake.
func _add_legacy_layers() -> void:
	if _terrain == null:
		return
	var vision := _terrain.get_node_or_null("VisionBlockTiles") as TileMapLayer
	if vision != null:
		for tile_cell: Vector2i in vision.get_used_cells():
			_blockers[world_to_cell(vision.to_global(vision.map_to_local(tile_cell)))] = true
	var legacy_crumble := _terrain.get_node_or_null("CrumbleTiles") as TileMapLayer
	if legacy_crumble != null:
		_add_solid_layer(legacy_crumble)
	var legacy_one_way := _terrain.get_node_or_null("CrumbleOneWayTiles") as TileMapLayer
	if legacy_one_way != null:
		for tile_cell: Vector2i in legacy_one_way.get_used_cells():
			_one_way_cells[world_to_cell(legacy_one_way.to_global(legacy_one_way.map_to_local(tile_cell)))] = true


func _add_occluder_blockers() -> void:
	if not is_inside_tree():
		return
	var room := _room_cell_rect()
	for node: Node in get_tree().get_nodes_in_group(OCCLUDER_GROUP):
		if not is_instance_valid(node) or not node.has_method("is_occluding"):
			continue
		if not bool(node.call("is_occluding")):
			continue
		if node.has_method("get_occluder_cells"):
			for cell: Vector2i in node.call("get_occluder_cells"):
				if room.has_point(cell):
					_blockers[cell] = true
			if node.has_method("get_occluder_one_way_cells"):
				for cell: Vector2i in node.call("get_occluder_one_way_cells"):
					if room.has_point(cell):
						_one_way_cells[cell] = true
			continue
		if not node.has_method("get_world_rect"):
			continue
		var rect: Rect2 = node.call("get_world_rect")
		for cell: Vector2i in _cells_in_world_rect(rect, room):
			_blockers[cell] = true


func _resolve_terrain() -> void:
	if _terrain == null and terrain_path != NodePath():
		var candidate := get_node_or_null(terrain_path)
		if candidate != null:
			_terrain = candidate.get_node_or_null("Terrain") if candidate.name != "Terrain" else candidate
	if _solid_tiles == null and _terrain != null:
		_solid_tiles = _terrain.get_node_or_null("SolidTiles") as TileMapLayer


func _current_player_cell() -> Vector2i:
	if not is_instance_valid(_player):
		return Vector2i(2147483647, 2147483647)
	return world_to_cell(_player.global_position)


func _hero_world_rect(player_position: Vector2) -> Rect2:
	return Rect2(player_position + hero_body_rect.position, hero_body_rect.size)


## Changes when the hero body starts or stops overlapping a zone, or when it is
## fully inside. Sub-cell movement across a zone edge must trigger a new reveal,
## otherwise the hero can straddle the edge while the zone is still dark.
func _zone_overlap_signature() -> String:
	if not is_inside_tree() or not is_instance_valid(_player):
		return ""
	var hero := _hero_world_rect(_player.global_position)
	var entries: Array[String] = []
	for node: Node in get_tree().get_nodes_in_group(ZONE_GROUP):
		if not is_instance_valid(node) or not node.has_method("get_world_rect"):
			continue
		var rect: Rect2 = node.call("get_world_rect")
		var overlaps := 1 if rect.intersects(hero) else 0
		var fully := 1 if rect.encloses(hero) else 0
		entries.append("%d:%d%d" % [node.get_instance_id(), overlaps, fully])
	entries.sort()
	return "|".join(entries)


func _room_cell_rect() -> Rect2i:
	return Rect2i(map_origin_cell, map_size_cells)


func _view_bounds_cells() -> Rect2i:
	var room := _room_cell_rect()
	if not is_inside_tree():
		return room
	var camera := get_viewport().get_camera_2d()
	if camera == null:
		return room
	var view_size := Vector2(get_viewport().get_visible_rect().size) / camera.zoom
	var top_left := camera.get_screen_center_position() - view_size * 0.5
	var start := world_to_cell(top_left)
	var end := world_to_cell(top_left + view_size)
	var view := Rect2i(start, end - start + Vector2i.ONE).grow(1)
	return view.intersection(room)


func _id_to_cell(cell_id: String) -> Variant:
	var prefix := "%s:" % level_id
	if not cell_id.begins_with(prefix):
		return null
	var coords := cell_id.substr(prefix.length()).split(",", false)
	if coords.size() != 2:
		return null
	if not coords[0].is_valid_int() or not coords[1].is_valid_int():
		return null
	return Vector2i(int(coords[0]), int(coords[1]))


## Repaints the mask texture the fog shader reads.
##
## The mask holds one texel block per cell: alpha is the fog opacity, red is the
## reveal flash and green is the signed distance to the border. It is rebuilt
## from a cached base plus the cells that are currently animating, so a reveal
## wave costs a memcpy and a handful of fill_rect calls per frame instead of
## walking the whole room.
func _update_mask_image(now: float = -1.0) -> void:
	if now < 0.0:
		now = _now()
	var mask_size := get_mask_size_pixels()
	if mask_size.x <= 0 or mask_size.y <= 0:
		return
	if _mask_image == null or _mask_image.get_size() != mask_size:
		_mask_image = Image.create_empty(mask_size.x, mask_size.y, false, Image.FORMAT_RGBA8)
		_mask_base = Image.create_empty(mask_size.x, mask_size.y, false, Image.FORMAT_RGBA8)
		_mask_texture = null
		_mask_base_dirty = true
	if _mask_base == null or _mask_base.get_size() != mask_size:
		_mask_base = Image.create_empty(mask_size.x, mask_size.y, false, Image.FORMAT_RGBA8)
		_mask_base_dirty = true
	if _mask_base_dirty:
		_rebuild_mask_base()
	_mask_image.copy_from(_mask_base)
	_apply_mask_animation(now)

	if _mask_texture == null:
		_mask_texture = ImageTexture.create_from_image(_mask_image)
	else:
		_mask_texture.update(_mask_image)
	_sync_mask_quad()


## Binary revealed/fogged field plus the signed distance to the border that the
## shader cuts the tendrils out of. Only rebuilt when the revealed set changes.
##
## The distance is a chamfer transform over the cell grid (3-4 weights, two
## passes), so the middle of a cell has the same continuous value the shader
## interpolates between cell centres. Encoding it costs one channel and makes
## the wobbling cut land on any pixel instead of on a cell edge.
func _rebuild_mask_base() -> void:
	_mask_base_dirty = false
	var cells := map_size_cells
	if cells.x <= 0 or cells.y <= 0:
		return
	var count := cells.x * cells.y
	var far := 4096.0
	var fog_depth := PackedFloat32Array()
	var lit_depth := PackedFloat32Array()
	fog_depth.resize(count)
	lit_depth.resize(count)
	for index: int in count:
		var cell := _mask_index_to_cell(index)
		var fogged := not is_cell_lit(cell)
		# fog_depth is the distance to the nearest revealed cell and the other
		# way round, so the revealed cells seed the fog field and vice versa.
		fog_depth[index] = far if fogged else 0.0
		lit_depth[index] = 0.0 if fogged else far
	_chamfer(fog_depth, cells.x, cells.y)
	_chamfer(lit_depth, cells.x, cells.y)

	_mask_base.fill(Color(0.0, 0.5, 0.0, 0.0))
	var pixels := float(cell_size.x)
	for index: int in count:
		var cell := _mask_index_to_cell(index)
		var rect := _mask_cell_rect(cell)
		if rect.size.x <= 0 or rect.size.y <= 0:
			continue
		var fogged := not is_cell_lit(cell)
		var depth: float = fog_depth[index] if fogged else lit_depth[index]
		# Chamfer runs cell centre to cell centre in thirds of a cell; the border
		# sits half a cell further in, so the signed value is zero on the edge.
		var signed_pixels := (depth / 3.0 - 0.5) * pixels
		if not fogged:
			signed_pixels = -signed_pixels
		var encoded := clampf(
			0.5 + signed_pixels / (2.0 * MASK_DISTANCE_PIXELS), 0.0, 1.0
		)
		_mask_base.fill_rect(rect, Color(0.0, encoded, 0.0, 1.0 if fogged else 0.0))


## Two-pass 3-4 chamfer distance transform, in thirds of a cell.
func _chamfer(field: PackedFloat32Array, width: int, height: int) -> void:
	for y: int in height:
		for x: int in width:
			var index := y * width + x
			var best := field[index]
			if best <= 0.0:
				continue
			if x > 0:
				best = minf(best, field[index - 1] + 3.0)
			if y > 0:
				best = minf(best, field[index - width] + 3.0)
				if x > 0:
					best = minf(best, field[index - width - 1] + 4.0)
				if x < width - 1:
					best = minf(best, field[index - width + 1] + 4.0)
			field[index] = best
	for y: int in range(height - 1, -1, -1):
		for x: int in range(width - 1, -1, -1):
			var index := y * width + x
			var best := field[index]
			if best <= 0.0:
				continue
			if x < width - 1:
				best = minf(best, field[index + 1] + 3.0)
			if y < height - 1:
				best = minf(best, field[index + width] + 3.0)
				if x < width - 1:
					best = minf(best, field[index + width + 1] + 4.0)
				if x > 0:
					best = minf(best, field[index + width - 1] + 4.0)
			field[index] = best


func _mask_index_to_cell(index: int) -> Vector2i:
	return Vector2i(
		map_origin_cell.x + index % map_size_cells.x,
		map_origin_cell.y + index / map_size_cells.x
	)


## Overlays the reveal wave (fog evaporating from the hero outwards, which the
## shader turns into a ragged receding front) and the focus spotlight.
func _apply_mask_animation(now: float) -> void:
	var finished: Array[Vector2i] = []
	for cell: Vector2i in _ripple:
		var alpha := _ripple_alpha(cell, now)
		if now - float(_ripple[cell]) >= reveal_seconds:
			finished.append(cell)
			continue
		_write_mask_cell(cell, alpha, _ripple_flash(cell, now))
	for cell: Vector2i in finished:
		_ripple.erase(cell)
		_write_mask_cell(cell, 1.0 if not is_cell_lit(cell) else 0.0, 0.0)

	if _focus_cells.is_empty() and _focus_zone == null:
		return
	var room := _room_cell_rect()
	for y: int in range(room.position.y, room.end.y):
		for x: int in range(room.position.x, room.end.x):
			var cell := Vector2i(x, y)
			var focus := _focus_alpha_at(cell, now)
			if focus <= 0.0:
				continue
			var rect := _mask_cell_rect(cell)
			if rect.size.x <= 0 or rect.size.y <= 0:
				continue
			_mask_image.fill_rect(rect, Color(0.0, _mask_cell_distance(cell), 0.0, clampf(focus, 0.0, 1.0)))


func _write_mask_cell(cell: Vector2i, alpha: float, flash: float) -> void:
	if _mask_image == null:
		return
	var rect := _mask_cell_rect(cell)
	if rect.size.x <= 0 or rect.size.y <= 0:
		return
	_mask_image.fill_rect(
		rect,
		Color(clampf(flash, 0.0, 1.0), _mask_cell_distance(cell), 0.0, clampf(alpha, 0.0, 1.0))
	)


## Encoded border distance of a cell, read back from the base so the animation
## only has to paint opacity and flash.
func _mask_cell_distance(cell: Vector2i) -> float:
	if _mask_base == null:
		return 0.5
	var rect := _mask_cell_rect(cell)
	if rect.size.x <= 0 or rect.size.y <= 0:
		return 0.5
	return _mask_base.get_pixel(rect.position.x, rect.position.y).g


## Mask-local pixel rect of a cell, clamped to the mask, empty when outside.
func _mask_cell_rect(cell: Vector2i) -> Rect2i:
	if _mask_image == null:
		return Rect2i()
	var local := (cell - map_origin_cell) * cell_size
	return Rect2i(local, cell_size).intersection(
		Rect2i(Vector2i.ZERO, _mask_image.get_size())
	)


## Keeps the quad that draws the mask in step with the room bounds.
func _sync_mask_quad() -> void:
	if _mask_texture == null or not is_inside_tree():
		return
	if _mask_sprite == null:
		_mask_sprite = Sprite2D.new()
		_mask_sprite.name = "FogMask"
		_mask_sprite.centered = false
		_mask_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_mask_material = ShaderMaterial.new()
		_mask_material.shader = FOG_SHADER
		_mask_sprite.material = _mask_material
		add_child(_mask_sprite)
	_mask_sprite.texture = _mask_texture
	_mask_sprite.position = to_local(Vector2(get_mask_origin_pixels()))
	_apply_mask_shader_parameters()


func _apply_mask_shader_parameters() -> void:
	if _mask_material == null:
		return
	_mask_material.set_shader_parameter("fog_color", fog_color)
	_mask_material.set_shader_parameter("mask_tex", _mask_texture)
	_mask_material.set_shader_parameter("mask_pixels", Vector2(get_mask_size_pixels()))
	_mask_material.set_shader_parameter("cell_pixels", Vector2(cell_size))
	_mask_material.set_shader_parameter("distance_range", MASK_DISTANCE_PIXELS)
	_mask_material.set_shader_parameter("tendril_pixels", tendril_pixels)
	_mask_material.set_shader_parameter("edge_softness", edge_softness)
	_mask_material.set_shader_parameter("noise_scale", edge_noise_scale)
	_mask_material.set_shader_parameter("noise_grain", edge_noise_grain)
	_mask_material.set_shader_parameter("noise_speed", edge_noise_speed)
	_mask_material.set_shader_parameter("noise_warp", edge_noise_warp)
	_mask_material.set_shader_parameter("breath_pixels", breath_pixels)
	_mask_material.set_shader_parameter("breath_scale", breath_scale)
	_mask_material.set_shader_parameter("breath_speed", breath_speed)
	_mask_material.set_shader_parameter("dither_strength", dither_strength)
	_mask_material.set_shader_parameter("dither_scale", dither_scale)


## Drops the mask and the quad texture, for example on a room switch.
func _release_mask() -> void:
	_mask_image = null
	_mask_base = null
	_mask_texture = null
	_mask_base_dirty = true
	if _mask_sprite != null:
		_mask_sprite.texture = null


func _cells_per_chunk() -> Vector2i:
	return Vector2i(
		ceili(float(chunk_size_pixels.x) / float(cell_size.x)),
		ceili(float(chunk_size_pixels.y) / float(cell_size.y))
	)


func _is_inside_map(cell: Vector2i) -> bool:
	return (
		cell.x >= map_origin_cell.x
		and cell.y >= map_origin_cell.y
		and cell.x < map_origin_cell.x + map_size_cells.x
		and cell.y < map_origin_cell.y + map_size_cells.y
	)


func _is_fog_enabled() -> bool:
	var settings := _settings_source
	if settings == null or not settings.has_method("is_fog_enabled"):
		return true
	return bool(settings.call("is_fog_enabled"))


func _is_one_way_occlusion_enabled() -> bool:
	var settings := _settings_source
	if settings == null or not settings.has_method("is_one_way_occlusion_enabled"):
		return true
	return bool(settings.call("is_one_way_occlusion_enabled"))


func _get_persistence_source() -> Object:
	if _persistence_source_is_bound:
		return _persistence_source
	return null


func _warn_once_missing_player() -> void:
	if _warned_missing_player:
		return
	_warned_missing_player = true
	push_warning("FogOfWar has no player; drawing saved exploration only.")


static func _is_room_data(resource: Resource) -> bool:
	if resource == null:
		return false
	var script := resource.get_script() as Script
	while script != null:
		if script == ROOM_DATA_SCRIPT:
			return true
		script = script.get_base_script()
	return false
