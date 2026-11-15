class_name CrumbleRuntime
extends Node2D

## Drives the two crumble tile layers of the active room.
##
## Each painted cell is independent: standing on it shakes the tile, then the
## cell is erased from the TileMapLayer (visual and collision both disappear),
## and it is written back after the respawn delay. One-way crumble tiles keep
## their one-way physics from the TileSet, so they can be passed from below and
## stand on the top face only. Solid crumble tiles block every direction.
##
## The runtime is bound to a room through WorldSession.register_room_extension,
## like FogOfWar: bind_room_with_origin() gives it the current terrain and the
## player, so it never drives cells of rooms the player is not in.

signal cell_broken(cell: Vector2i)
signal cell_restored(cell: Vector2i)

const CELL_PIXELS := 8

@export var player_path: NodePath
@export var terrain_path: NodePath
@export var shake_seconds := 0.25
@export var respawn_seconds := 1.5
@export var debris_gravity := 420.0
@export var debris_life := 0.55
## Tiles with these atlas coordinates in SolidTiles crumble when stood on.
@export var crumble_solid_atlas := Vector2i(3, 0)
@export var crumble_one_way_atlas := Vector2i(3, 4)

var _player: Node2D
var _layers: Array[TileMapLayer] = []
var _room_pixel_rect := Rect2()
var _cells: Dictionary[String, Dictionary] = {}
var _debris: Array[Dictionary] = []
var _warned_missing_player := false


func _ready() -> void:
	if _player == null and player_path != NodePath():
		_player = get_node_or_null(player_path) as Node2D
	if terrain_path != NodePath():
		var terrain := get_node_or_null(terrain_path)
		if terrain != null:
			_bind_terrain(terrain, Rect2())


func bind_player(player: Node2D) -> void:
	_player = player
	_warned_missing_player = false


func bind_room(room_data: Resource, terrain_root: Node, origin_chunk: Variant = null) -> bool:
	return bind_room_with_origin(room_data, terrain_root, Vector2i(origin_chunk) if origin_chunk != null else Vector2i.ZERO)


func bind_room_with_origin(room_data: Resource, terrain_root: Node, origin_chunk: Vector2i) -> bool:
	_restore_all()
	_layers.clear()
	if room_data == null or terrain_root == null:
		return false
	var terrain := terrain_root.get_node_or_null("Terrain")
	if terrain == null:
		return false
	var size_chunks: Vector2i = room_data.get("room_size_chunks")
	var room_rect := Rect2(
		Vector2(origin_chunk * Vector2i(320, 180)),
		Vector2(size_chunks * Vector2i(320, 180))
	)
	return _bind_terrain(terrain, room_rect)


func _bind_terrain(terrain: Node, room_rect: Rect2) -> bool:
	_layers.clear()
	var solid := terrain.get_node_or_null("SolidTiles") as TileMapLayer
	var one_way := terrain.get_node_or_null("CrumbleOneWayTiles") as TileMapLayer
	var legacy_solid := terrain.get_node_or_null("CrumbleTiles") as TileMapLayer
	if solid != null:
		_layers.append(solid)
	if legacy_solid != null:
		_layers.append(legacy_solid)
	if one_way != null:
		_layers.append(one_way)
	if _layers.is_empty():
		# Older rooms are not required to author a crumble layer.
		_room_pixel_rect = Rect2()
		return true
	_room_pixel_rect = room_rect
	return true


func clear_room() -> void:
	_restore_all()
	_layers.clear()
	_cells.clear()
	_room_pixel_rect = Rect2()


func _physics_process(delta: float) -> void:
	_tick(delta)


## Test/scripting seam: start the shake for one cell without a player.
func trigger_cell(layer: TileMapLayer, cell: Vector2i) -> bool:
	if layer == null or layer.get_cell_source_id(cell) == -1:
		return false
	if layer.name == "SolidTiles":
		var atlas := layer.get_cell_atlas_coords(cell)
		if atlas != crumble_solid_atlas and atlas != crumble_one_way_atlas:
			return false
	var key := _cell_key(layer, cell)
	if _cells.has(key):
		return false
	_cells[key] = {
		"layer": layer,
		"cell": cell,
		"state": 0,
		"timer": shake_seconds,
	}
	queue_redraw()
	return true


## Test/scripting seam: advance the state machine without the scene tree.
func tick(delta: float) -> void:
	_tick(delta)


func get_active_cells() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for entry: Dictionary in _cells.values():
		result.append(entry["cell"])
	return result


func _tick(delta: float) -> void:
	if not _layers.is_empty() and is_instance_valid(_player) and _player.has_method("is_on_floor"):
		if _player.call("is_on_floor") and _is_inside_room(_player.global_position):
			_probe_player_feet()
	_advance_cells(delta)
	_advance_debris(delta)
	if not _cells.is_empty():
		queue_redraw()


func _probe_player_feet() -> void:
	var feet := _player.global_position + Vector2(0, 3)
	for x_offset: int in [-3, 0, 3]:
		var world_point := feet + Vector2(x_offset, 0)
		for layer: TileMapLayer in _layers:
			var cell := layer.local_to_map(layer.to_local(world_point))
			if layer.get_cell_source_id(cell) != -1:
				trigger_cell(layer, cell)


func _is_inside_room(world_position: Vector2) -> bool:
	return _room_pixel_rect.size == Vector2.ZERO or _room_pixel_rect.has_point(world_position)


func _advance_cells(delta: float) -> void:
	for key: String in _cells.keys():
		var entry: Dictionary = _cells[key]
		entry["timer"] = float(entry["timer"]) - delta
		if float(entry["timer"]) > 0.0:
			continue
		if int(entry["state"]) == 0:
			_break_cell(entry)
		else:
			_restore_cell(key, entry)


func _break_cell(entry: Dictionary) -> void:
	var layer: TileMapLayer = entry["layer"]
	var cell: Vector2i = entry["cell"]
	entry["state"] = 1
	entry["timer"] = respawn_seconds
	entry["source_id"] = layer.get_cell_source_id(cell)
	entry["atlas"] = layer.get_cell_atlas_coords(cell)
	entry["alternative"] = layer.get_cell_alternative_tile(cell)
	layer.erase_cell(cell)
	_spawn_debris(layer, cell, entry["source_id"], entry["atlas"])
	_notify_fog()
	cell_broken.emit(cell)


func _restore_cell(key: String, entry: Dictionary) -> void:
	var layer: TileMapLayer = entry["layer"]
	var cell: Vector2i = entry["cell"]
	layer.set_cell(cell, int(entry["source_id"]), entry["atlas"], int(entry["alternative"]))
	_cells.erase(key)
	_notify_fog()
	cell_restored.emit(cell)
	queue_redraw()


func _restore_all() -> void:
	for key: String in _cells.keys():
		var entry: Dictionary = _cells[key]
		if int(entry["state"]) == 1:
			_restore_cell(key, entry)
	_cells.clear()
	queue_redraw()


func _spawn_debris(layer: TileMapLayer, cell: Vector2i, source_id: int, atlas: Vector2i) -> void:
	var source: TileSetAtlasSource = null
	if layer.tile_set != null:
		source = layer.tile_set.get_source(source_id) as TileSetAtlasSource
	if source == null or source.texture == null:
		return
	var atlas_texture := AtlasTexture.new()
	atlas_texture.atlas = source.texture
	atlas_texture.region = Rect2(atlas * source.texture_region_size, source.texture_region_size)
	var sprite := Sprite2D.new()
	sprite.texture = atlas_texture
	sprite.centered = true
	sprite.z_index = 9
	add_child(sprite)
	sprite.global_position = layer.to_global(layer.map_to_local(cell))
	_debris.append({
		"sprite": sprite,
		"velocity": Vector2(0.0, -40.0),
		"life": debris_life,
	})


func _advance_debris(delta: float) -> void:
	var index := _debris.size() - 1
	while index >= 0:
		var entry: Dictionary = _debris[index]
		var sprite: Sprite2D = entry["sprite"]
		if not is_instance_valid(sprite):
			_debris.remove_at(index)
			index -= 1
			continue
		var velocity: Vector2 = entry["velocity"]
		velocity.y += debris_gravity * delta
		entry["velocity"] = velocity
		sprite.global_position += velocity * delta
		entry["life"] = float(entry["life"]) - delta
		if float(entry["life"]) <= 0.0 or not _is_inside_room(sprite.global_position):
			sprite.queue_free()
			_debris.remove_at(index)
		else:
			sprite.modulate.a = clampf(float(entry["life"]) / debris_life, 0.0, 1.0)
		index -= 1


func _draw() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	for entry: Dictionary in _cells.values():
		if int(entry["state"]) != 0:
			continue
		var layer: TileMapLayer = entry["layer"]
		var cell: Vector2i = entry["cell"]
		var center := layer.to_global(layer.map_to_local(cell))
		var jitter := 1.0 if int(now * 60.0) % 2 == 0 else -1.0
		var rect := Rect2(center - Vector2(CELL_PIXELS, CELL_PIXELS) * 0.5 + Vector2(jitter, 0), Vector2(CELL_PIXELS, CELL_PIXELS))
		draw_rect(rect, Color(1.0, 1.0, 1.0, 0.75), false, 1.0)


func _notify_fog() -> void:
	if is_inside_tree():
		get_tree().call_group(&"fog_of_war", "request_refresh")


func _cell_key(layer: TileMapLayer, cell: Vector2i) -> String:
	return "%d:%d,%d" % [layer.get_instance_id(), cell.x, cell.y]
