class_name FogOfWar
extends Node2D

const FOG_VISIBILITY: Script = preload("res://scripts/world/fog_visibility.gd")

@export var player_path: NodePath
@export var solid_tiles_path: NodePath
@export var map_origin_cell := Vector2i(-24, -12)
@export var map_size_cells := Vector2i(80, 32)
@export var cell_size := Vector2i(8, 8)
@export var chunk_size_pixels := Vector2i(320, 180)
@export var level_id := "level_01"
@export var fog_color := Color.BLACK

var currently_visible: Dictionary[Vector2i, bool] = {}

var _explored_cells: Dictionary[Vector2i, bool] = {}
var _mask_image: Image
var _mask_texture: ImageTexture
var _player: Node2D
var _solid_tiles: TileMapLayer
var _warned_missing_player := false
var _warned_missing_solid_tiles := false


func _ready() -> void:
	_player = get_node_or_null(player_path) as Node2D
	_solid_tiles = get_node_or_null(solid_tiles_path) as TileMapLayer
	_load_saved_progress()
	reveal_from_player()


func _process(_delta: float) -> void:
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


func get_mask_image() -> Image:
	return _mask_image


func get_mask_texture() -> ImageTexture:
	return _mask_texture


func set_room_chunks(room_origin_chunk: Vector2i, room_size_chunks: Vector2i) -> void:
	var cells_per_chunk := _cells_per_chunk()
	map_origin_cell = Vector2i(
		room_origin_chunk.x * cells_per_chunk.x,
		room_origin_chunk.y * cells_per_chunk.y
	)
	map_size_cells = Vector2i(
		room_size_chunks.x * cells_per_chunk.x,
		room_size_chunks.y * cells_per_chunk.y
	)
	_mask_image = null
	_mask_texture = null
	queue_redraw()


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
	reveal_from_cell(origin, _collect_blockers())


func reveal_from_cell(origin: Vector2i, blockers: Dictionary) -> void:
	var visibility: RefCounted = FOG_VISIBILITY.new()
	currently_visible = visibility.compute_room_visible_cells(
		origin,
		map_origin_cell,
		map_size_cells,
		blockers
	)

	var save_manager := _get_root_node("SaveManager")
	for cell: Vector2i in currently_visible.keys():
		if not _is_inside_map(cell):
			continue
		var is_new := not _explored_cells.has(cell)
		_explored_cells[cell] = true
		if is_new and save_manager != null and save_manager.has_method("mark_cell_explored"):
			save_manager.call("mark_cell_explored", cell_to_id(cell))

	_update_mask_image()
	queue_redraw()


func _draw() -> void:
	if not _is_fog_enabled():
		return
	for y: int in range(map_origin_cell.y, map_origin_cell.y + map_size_cells.y):
		for x: int in range(map_origin_cell.x, map_origin_cell.x + map_size_cells.x):
			var cell := Vector2i(x, y)
			if currently_visible.has(cell):
				continue
			draw_rect(_cell_rect(cell), fog_color, true)


func _load_saved_progress() -> void:
	var save_manager := _get_root_node("SaveManager")
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


func _update_mask_image() -> void:
	var mask_size := Vector2i(
		map_size_cells.x * cell_size.x,
		map_size_cells.y * cell_size.y
	)
	if mask_size.x <= 0 or mask_size.y <= 0:
		return
	if _mask_image == null or _mask_image.get_size() != mask_size:
		_mask_image = Image.create_empty(mask_size.x, mask_size.y, false, Image.FORMAT_RGBA8)
		_mask_texture = null

	_mask_image.fill(fog_color)
	for cell: Vector2i in currently_visible.keys():
		if not _is_inside_map(cell):
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
	var settings := _get_root_node("GlobalSettings")
	if settings == null or not settings.has_method("is_fog_enabled"):
		return true
	return bool(settings.call("is_fog_enabled"))


func _get_root_node(node_name: String) -> Node:
	if not is_inside_tree():
		return null
	return get_tree().root.get_node_or_null(node_name)


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
