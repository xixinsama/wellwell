class_name FogOfWar
extends Node2D

const FOG_VISIBILITY: Script = preload("res://scripts/world/fog_visibility.gd")
const ROOM_DATA_SCRIPT: Script = preload("res://scripts/world/room_data.gd")
const TERRAIN_LAYER_NAMES: Array[String] = [
	"BackTiles", "SolidTiles", "GlassTiles", "VisionBlockTiles", "DetailTiles", "MarkerTiles"
]

@export var player_path: NodePath
@export var solid_tiles_path: NodePath
@export var vision_block_tiles_path: NodePath
@export var glass_tiles_path: NodePath
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
var _vision_block_tiles: TileMapLayer
var _glass_tiles: TileMapLayer
var _persistence_source: Object
var _persistence_source_is_bound := false
var _warned_missing_player := false
var _warned_missing_solid_tiles := false
var _player_is_explicitly_bound := false
var _room_binding_is_explicit := false
var _room_is_bound := false
var _has_exact_room_bounds := false
var _room_origin_pixels := Vector2i.ZERO
var _room_size_pixels := Vector2i.ZERO


func _ready() -> void:
	if not _player_is_explicitly_bound and player_path != NodePath():
		_player = get_node_or_null(player_path) as Node2D
	if not _room_binding_is_explicit and solid_tiles_path != NodePath():
		_solid_tiles = get_node_or_null(solid_tiles_path) as TileMapLayer
	if not _room_binding_is_explicit and vision_block_tiles_path != NodePath():
		_vision_block_tiles = get_node_or_null(vision_block_tiles_path) as TileMapLayer
	if not _room_binding_is_explicit and glass_tiles_path != NodePath():
		_glass_tiles = get_node_or_null(glass_tiles_path) as TileMapLayer
	_load_saved_progress()
	reveal_from_player()


func _process(_delta: float) -> void:
	reveal_from_player()


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


func is_cell_explored(cell: Vector2i) -> bool:
	return _explored_cells.has(cell)


func get_mask_image() -> Image:
	return _mask_image


func get_mask_texture() -> ImageTexture:
	return _mask_texture


func bind_player(player: Node2D) -> void:
	_player_is_explicitly_bound = true
	_player = player
	_warned_missing_player = false


func bind_room(room_data: RoomData, terrain_root: Node) -> bool:
	if not _is_room_data(room_data) or terrain_root == null:
		return false
	if terrain_root.get_node_or_null("Background") == null:
		return false
	var terrain := terrain_root.get_node_or_null("Terrain")
	if terrain == null:
		return false
	var layers: Dictionary[String, TileMapLayer] = {}
	for layer_name: String in TERRAIN_LAYER_NAMES:
		var layer := terrain.get_node_or_null(layer_name) as TileMapLayer
		if layer == null:
			return false
		layers[layer_name] = layer

	clear_room()
	_room_binding_is_explicit = true
	_room_is_bound = true
	level_id = room_data.room_id
	_solid_tiles = layers["SolidTiles"]
	_vision_block_tiles = layers["VisionBlockTiles"]
	_glass_tiles = layers["GlassTiles"]
	set_room_chunks(room_data.room_origin_chunk, room_data.room_size_chunks)
	_load_saved_progress()
	_warned_missing_solid_tiles = false
	return true


func clear_room() -> void:
	_room_binding_is_explicit = true
	_room_is_bound = false
	_has_exact_room_bounds = false
	_room_origin_pixels = Vector2i.ZERO
	_room_size_pixels = Vector2i.ZERO
	_solid_tiles = null
	_vision_block_tiles = null
	_glass_tiles = null
	currently_visible.clear()
	_explored_cells.clear()
	_mask_image = null
	_mask_texture = null
	queue_redraw()


func bind_persistence_source(source: Object) -> void:
	_persistence_source = source
	_persistence_source_is_bound = true


func clear_persistence_source() -> void:
	_persistence_source = null
	_persistence_source_is_bound = false


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
	queue_redraw()


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
	reveal_from_cell(origin, _collect_blockers())


func reveal_from_cell(origin: Vector2i, blockers: Dictionary) -> void:
	var visibility: RefCounted = FOG_VISIBILITY.new()
	currently_visible = visibility.compute_room_visible_cells(
		origin,
		map_origin_cell,
		map_size_cells,
		blockers
	)

	var save_manager := _get_persistence_source()
	if save_manager != null and save_manager.has_method("mark_chunk_explored"):
		var chunk := Vector2i(floori(float(origin.x) / _cells_per_chunk().x), floori(float(origin.y) / _cells_per_chunk().y))
		save_manager.call("mark_chunk_explored", "%s:chunk:%d,%d" % [level_id, chunk.x, chunk.y])
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
	var save_manager := _get_persistence_source()
	if save_manager == null:
		return
	if save_manager.has_method("get_explored_cells"):
		var ids: Array[String] = []
		ids.assign(save_manager.call("get_explored_cells"))
		load_explored_cells(ids)


func _collect_blockers() -> Dictionary[Vector2i, bool]:
	var blockers: Dictionary[Vector2i, bool] = {}
	if _vision_block_tiles == null and vision_block_tiles_path != NodePath():
		_vision_block_tiles = get_node_or_null(vision_block_tiles_path) as TileMapLayer
	if _vision_block_tiles != null:
		_add_layer_blockers(_vision_block_tiles, blockers)
	if _solid_tiles == null and solid_tiles_path != NodePath():
		_solid_tiles = get_node_or_null(solid_tiles_path) as TileMapLayer
	if _solid_tiles != null:
		_add_layer_blockers(_solid_tiles, blockers)
	if _glass_tiles == null and glass_tiles_path != NodePath():
		_glass_tiles = get_node_or_null(glass_tiles_path) as TileMapLayer
	if _glass_tiles != null:
		_add_layer_blockers(_glass_tiles, blockers)
	if _solid_tiles == null and blockers.is_empty():
		_warn_once_missing_solid_tiles()
	return blockers


func _add_layer_blockers(layer: TileMapLayer, blockers: Dictionary[Vector2i, bool]) -> void:
	for tile_cell: Vector2i in layer.get_used_cells():
		var world_position := layer.to_global(layer.map_to_local(tile_cell))
		blockers[world_to_cell(world_position)] = true


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


func _get_persistence_source() -> Object:
	if _persistence_source_is_bound:
		return _persistence_source
	if _has_isolated_preview_ancestor():
		return null
	return _get_root_node("SaveManager")


func _has_isolated_preview_ancestor() -> bool:
	var ancestor := get_parent()
	while ancestor != null:
		if ancestor.has_method("isolates_preview_persistence"):
			return bool(ancestor.call("isolates_preview_persistence"))
		ancestor = ancestor.get_parent()
	return false


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


static func _is_room_data(resource: Resource) -> bool:
	return resource != null and resource.get_script() == ROOM_DATA_SCRIPT
