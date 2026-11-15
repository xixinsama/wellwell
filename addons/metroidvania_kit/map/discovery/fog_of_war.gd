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

const FOG_VISIBILITY: Script = preload("res://addons/metroidvania_kit/map/discovery/fog_visibility.gd")
const ROOM_DATA_SCRIPT: Script = preload("res://addons/platformer_kit/world/data/room_data.gd")
const ZONE_GROUP := &"fog_zone"
const OCCLUDER_GROUP := &"fog_occluder"
const FOG_GROUP := &"fog_of_war"

@export var player_path: NodePath
@export var terrain_path: NodePath
@export var map_origin_cell := Vector2i(-24, -12)
@export var map_size_cells := Vector2i(80, 32)
@export var cell_size := Vector2i(8, 8)
@export var chunk_size_pixels := Vector2i(320, 180)
@export var level_id := "level_01"
@export var fog_color := Color.BLACK
@export var glass_tile_atlas := Vector2i(0, 3)
@export var reveal_seconds := 0.28
@export var reveal_stagger_seconds := 0.012
@export var reveal_flash_seconds := 0.12
## The hero volume used for zone membership, relative to the player origin
## (feet). The sprite is 10x10 and the feet origin is at its bottom edge.
@export var hero_body_rect := Rect2(-5, -10, 10, 10)

var currently_visible: Dictionary[Vector2i, bool] = {}

var _explored_cells: Dictionary[Vector2i, bool] = {}
var _dark_cells: Dictionary[Vector2i, bool] = {}
var _light_cells: Dictionary[Vector2i, bool] = {}
var _revealed_zones: Dictionary[String, bool] = {}
var _ripple: Dictionary[Vector2i, float] = {}
var _ripple_end := 0.0
var _mask_image: Image
var _mask_texture: ImageTexture
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
	var origin := _current_player_cell()
	var view := _view_bounds_cells()
	var zone_signature := _zone_overlap_signature()
	if origin != _last_origin_cell or view != _last_view_bounds or zone_signature != _last_zone_signature or _dirty:
		reveal_from_player()
	elif not _ripple.is_empty() and _now() < _ripple_end:
		queue_redraw()
	if _focus_zone != null or not _focus_cells.is_empty():
		queue_redraw()


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
	for cell_id: String in cell_ids:
		var parsed: Variant = _id_to_cell(cell_id)
		if parsed != null:
			_explored_cells[parsed] = true
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


func is_cell_lit(cell: Vector2i) -> bool:
	if _light_cells.has(cell):
		return true
	if _dark_cells.has(cell):
		return false
	return _explored_cells.has(cell)


func is_focus_active() -> bool:
	return _focus_zone != null


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
	_mask_image = null
	_mask_texture = null
	_last_origin_cell = Vector2i(2147483647, 2147483647)
	_last_view_bounds = Rect2i()
	_last_zone_signature = ""
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
	_mask_image = null
	_mask_texture = null
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
		var distance := Vector2(cell - origin).length() / distance_scale
		_ripple[cell] = now + distance * reveal_stagger_seconds
		_ripple_end = maxf(_ripple_end, _ripple[cell] + reveal_seconds)
		if save_manager != null and save_manager.has_method("mark_cell_explored"):
			save_manager.call("mark_cell_explored", cell_to_id(cell))
	_update_mask_image()
	queue_redraw()


func _draw() -> void:
	if not _is_fog_enabled():
		return
	var now := _now()
	var room := _room_cell_rect()
	for y: int in range(room.position.y, room.end.y):
		for x: int in range(room.position.x, room.end.x):
			var cell := Vector2i(x, y)
			if is_cell_lit(cell):
				if _ripple.has(cell):
					_draw_revealing_cell(cell, now)
				continue
			var alpha := 1.0
			if _ripple.has(cell):
				var start: float = _ripple[cell]
				if now >= start:
					alpha = clampf(1.0 - (now - start) / reveal_seconds, 0.0, 1.0)
					if alpha <= 0.0:
						_ripple.erase(cell)
						continue
			var color := fog_color
			if alpha < 1.0:
				color.a *= alpha
			draw_rect(_cell_rect(cell), color, true)
	_draw_focus(now)


func _draw_revealing_cell(cell: Vector2i, now: float) -> void:
	var start: float = _ripple[cell]
	if now < start:
		return
	var elapsed := now - start
	if elapsed >= reveal_seconds:
		_ripple.erase(cell)
		return
	if elapsed <= reveal_flash_seconds:
		var flash := 1.0 - elapsed / reveal_flash_seconds
		draw_rect(_cell_rect(cell), Color(1.0, 1.0, 1.0, 0.55 * flash), false, 1.0)


func _draw_focus(now: float) -> void:
	if _focus_cells.is_empty() and _focus_zone == null:
		return
	var strength := _focus_strength(now)
	if strength <= 0.0:
		if _focus_zone == null:
			_clear_focus()
		return
	var room := _room_cell_rect()
	var center := _focus_center
	for y: int in range(room.position.y, room.end.y):
		for x: int in range(room.position.x, room.end.x):
			var cell := Vector2i(x, y)
			if _focus_cells.has(cell):
				continue
			if not is_cell_lit(cell):
				continue
			var distance := Vector2(cell - center).length()
			var far := 1.0 - clampf(distance / maxf(_focus_max_distance, 1.0), 0.0, 1.0)
			var local := clampf((strength - far * 0.55) / 0.45, 0.0, 1.0)
			if local <= 0.0:
				continue
			var color := fog_color
			color.a *= local * _focus_alpha
			draw_rect(_cell_rect(cell), color, true)


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
			_ripple[cell] = now
			_ripple_end = maxf(_ripple_end, now + reveal_seconds)
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
	_add_door_blockers()
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
		for index in tile_data.get_collision_polygons_count(0):
			if tile_data.is_collision_polygon_one_way(0, index):
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


func _add_door_blockers() -> void:
	if not is_inside_tree():
		return
	var room := _room_cell_rect()
	for node: Node in get_tree().get_nodes_in_group(OCCLUDER_GROUP):
		if not is_instance_valid(node) or not node.has_method("is_occluding") or not node.has_method("get_world_rect"):
			continue
		if not bool(node.call("is_occluding")):
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


func _cell_rect(cell: Vector2i) -> Rect2:
	if _has_exact_room_bounds:
		var local_origin := (cell - map_origin_cell) * cell_size
		var remaining := _room_size_pixels - local_origin
		return Rect2(
			Vector2(_room_origin_pixels + local_origin),
			Vector2(mini(cell_size.x, remaining.x), mini(cell_size.y, remaining.y))
		)
	return Rect2(
		Vector2(cell.x * cell_size.x, cell.y * cell_size.y),
		Vector2(cell_size)
	)


func _update_mask_image() -> void:
	var mask_size := _room_size_pixels if _has_exact_room_bounds else Vector2i(
		map_size_cells.x * cell_size.x,
		map_size_cells.y * cell_size.y
	)
	if mask_size.x <= 0 or mask_size.y <= 0:
		return
	if _mask_image == null or _mask_image.get_size() != mask_size:
		_mask_image = Image.create_empty(mask_size.x, mask_size.y, false, Image.FORMAT_RGBA8)
		_mask_texture = null

	_mask_image.fill(fog_color)
	var room := _room_cell_rect()
	for y: int in range(room.position.y, room.end.y):
		for x: int in range(room.position.x, room.end.x):
			var cell := Vector2i(x, y)
			if not is_cell_lit(cell):
				continue
			var local_origin := Vector2i(
				(cell.x - map_origin_cell.x) * cell_size.x,
				(cell.y - map_origin_cell.y) * cell_size.y
			)
			_mask_image.fill_rect(Rect2i(local_origin, cell_size), Color.TRANSPARENT)

	if _mask_texture == null:
		_mask_texture = ImageTexture.create_from_image(_mask_image)
	else:
		_mask_texture.update(_mask_image)


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
