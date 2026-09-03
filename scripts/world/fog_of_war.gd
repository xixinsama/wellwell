class_name FogOfWar
extends Node2D

const FOG_VISIBILITY: Script = preload("res://scripts/world/fog_visibility.gd")

@export var player_path: NodePath
@export var solid_tiles_path: NodePath
@export var map_origin_cell := Vector2i(-24, -12)
@export var map_size_cells := Vector2i(80, 32)
@export var cell_size := Vector2i(8, 8)
@export var reveal_radius_cells := 12
@export var level_id := "level_01"
@export var fog_color := Color.BLACK
@export var update_interval := 0.08

var currently_visible: Dictionary[Vector2i, bool] = {}

var _explored_cells: Dictionary[Vector2i, bool] = {}
var _player: Node2D
var _solid_tiles: TileMapLayer
var _elapsed := 0.0
var _warned_missing_player := false
var _warned_missing_solid_tiles := false


func _ready() -> void:
	_player = get_node_or_null(player_path) as Node2D
	_solid_tiles = get_node_or_null(solid_tiles_path) as TileMapLayer
	_load_saved_progress()
	reveal_from_player()


func _physics_process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < update_interval:
		return
	_elapsed = 0.0
	reveal_from_player()


func world_to_cell(world_position: Vector2) -> Vector2i:
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


func is_cell_explored(cell: Vector2i) -> bool:
	return _explored_cells.has(cell)


func reveal_from_player() -> void:
	if not _is_fog_enabled():
		visible = false
		return
	visible = true

	if _player == null and player_path != NodePath():
		_player = get_node_or_null(player_path) as Node2D
	if _player == null:
		_warn_once_missing_player()
		queue_redraw()
		return

	var origin := world_to_cell(_player.global_position)
	var visibility: RefCounted = FOG_VISIBILITY.new()
	currently_visible = visibility.compute_visible_cells(
		origin,
		reveal_radius_cells,
		_collect_blockers()
	)

	var save_manager := get_node_or_null("/root/SaveManager")
	for cell: Vector2i in currently_visible.keys():
		if not _is_inside_map(cell):
			continue
		var is_new := not _explored_cells.has(cell)
		_explored_cells[cell] = true
		if is_new and save_manager != null and save_manager.has_method("mark_cell_explored"):
			save_manager.call("mark_cell_explored", cell_to_id(cell))

	queue_redraw()


func _draw() -> void:
	if not _is_fog_enabled():
		return
	for y: int in range(map_origin_cell.y, map_origin_cell.y + map_size_cells.y):
		for x: int in range(map_origin_cell.x, map_origin_cell.x + map_size_cells.x):
			var cell := Vector2i(x, y)
			if _explored_cells.has(cell):
				continue
			draw_rect(_cell_rect(cell), fog_color, true)


func _load_saved_progress() -> void:
	var save_manager := get_node_or_null("/root/SaveManager")
	if save_manager == null or not save_manager.has_method("start_or_continue"):
		return
	save_manager.call("start_or_continue", 1)
	if save_manager.has_method("get_explored_cells"):
		var ids: Array[String] = []
		ids.assign(save_manager.call("get_explored_cells"))
		load_explored_cells(ids)


func _collect_blockers() -> Dictionary[Vector2i, bool]:
	var blockers: Dictionary[Vector2i, bool] = {}
	if _solid_tiles == null and solid_tiles_path != NodePath():
		_solid_tiles = get_node_or_null(solid_tiles_path) as TileMapLayer
	if _solid_tiles == null:
		_warn_once_missing_solid_tiles()
		return blockers
	for tile_cell: Vector2i in _solid_tiles.get_used_cells():
		blockers[tile_cell] = true
	return blockers


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
	return Rect2(
		Vector2(cell.x * cell_size.x, cell.y * cell_size.y),
		Vector2(cell_size)
	)


func _is_inside_map(cell: Vector2i) -> bool:
	return (
		cell.x >= map_origin_cell.x
		and cell.y >= map_origin_cell.y
		and cell.x < map_origin_cell.x + map_size_cells.x
		and cell.y < map_origin_cell.y + map_size_cells.y
	)


func _is_fog_enabled() -> bool:
	var settings := get_node_or_null("/root/GlobalSettings")
	if settings == null or not settings.has_method("is_fog_enabled"):
		return true
	return bool(settings.call("is_fog_enabled"))


func _warn_once_missing_player() -> void:
	if _warned_missing_player:
		return
	_warned_missing_player = true
	push_warning("FogOfWar has no player; drawing saved exploration only.")


func _warn_once_missing_solid_tiles() -> void:
	if _warned_missing_solid_tiles:
		return
	_warned_missing_solid_tiles = true
	push_warning("FogOfWar has no solid tile layer; revealing without wall blocking.")
