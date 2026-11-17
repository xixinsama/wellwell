class_name RoomTerrainSnapshot
extends RefCounted

## Scans a baked room terrain scene once and remembers what every 8x8 cell is,
## so the precise map can paint explored cells without touching the live scene.
## The scan is cached by path and file modification time.

enum Kind {
	EMPTY = 0,
	BACK = 1,
	SOLID = 2,
	ONE_WAY = 3,
	GLASS = 4,
	LADDER = 5,
	CRUMBLE = 6,
	CRUMBLE_ONE_WAY = 7,
	VISION = 8,
}

const GLASS_ATLAS := Vector2i(0, 3)
const LADDER_ATLAS := Vector2i(0, 7)
const CRUMBLE_ATLAS := Vector2i(3, 0)
const CRUMBLE_ONE_WAY_ATLAS := Vector2i(3, 4)

static var _cache: Dictionary[String, Dictionary] = {}


## Returns {"size": Vector2i, "cells": Dictionary[Vector2i, int], "version": int}.
static func get_snapshot(terrain_scene_path: String) -> Dictionary:
	if terrain_scene_path.is_empty() or not ResourceLoader.exists(terrain_scene_path, "PackedScene"):
		return {"size": Vector2i.ZERO, "cells": {}, "version": 0}
	var modified := FileAccess.get_modified_time(terrain_scene_path)
	var cached: Dictionary = _cache.get(terrain_scene_path, {})
	if not cached.is_empty() and int(cached.get("modified", -1)) == modified:
		return cached
	var snapshot := _scan(terrain_scene_path)
	snapshot["modified"] = modified
	snapshot["version"] = int(cached.get("version", 0)) + 1
	_cache[terrain_scene_path] = snapshot
	return snapshot


static func clear_cache() -> void:
	_cache.clear()


static func _scan(terrain_scene_path: String) -> Dictionary:
	var cells: Dictionary[Vector2i, int] = {}
	var packed := ResourceLoader.load(
		terrain_scene_path,
		"PackedScene",
		ResourceLoader.CACHE_MODE_IGNORE
	) as PackedScene
	if packed == null:
		return {"size": Vector2i.ZERO, "cells": cells}
	var root := packed.instantiate()
	var terrain := root.get_node_or_null("Terrain")
	var size := Vector2i.ZERO
	if terrain != null:
		size = _scan_layers(terrain, cells)
	root.free()
	return {"size": size, "cells": cells}


static func _scan_layers(terrain: Node, cells: Dictionary[Vector2i, int]) -> Vector2i:
	var max_cell := Vector2i.ZERO
	var has_cells := false
	for layer_name: String in ["BackTiles", "SolidTiles", "VisionBlockTiles", "GlassTiles", "CrumbleTiles", "CrumbleOneWayTiles"]:
		var layer := terrain.get_node_or_null(layer_name) as TileMapLayer
		if layer == null:
			continue
		var is_back := layer_name == "BackTiles"
		var is_vision := layer_name == "VisionBlockTiles"
		var forced := Kind.EMPTY
		if layer_name == "GlassTiles":
			forced = Kind.GLASS
		elif layer_name == "CrumbleTiles":
			forced = Kind.CRUMBLE
		elif layer_name == "CrumbleOneWayTiles":
			forced = Kind.CRUMBLE_ONE_WAY
		for cell: Vector2i in layer.get_used_cells():
			var kind := forced
			if kind == Kind.EMPTY:
				kind = _cell_kind(layer, cell)
			if is_back:
				kind = Kind.BACK
			elif is_vision:
				kind = Kind.VISION
			if kind == Kind.EMPTY:
				continue
			# A foreground cell wins over the background fill of the same cell.
			if cells.get(cell, Kind.EMPTY) == Kind.BACK and kind != Kind.BACK:
				cells[cell] = kind
			elif not cells.has(cell):
				cells[cell] = kind
			max_cell = Vector2i(maxi(max_cell.x, cell.x), maxi(max_cell.y, cell.y))
			has_cells = true
	if not has_cells:
		return Vector2i.ZERO
	return max_cell + Vector2i.ONE


static func _cell_kind(layer: TileMapLayer, cell: Vector2i) -> int:
	var atlas := layer.get_cell_atlas_coords(cell)
	if atlas == GLASS_ATLAS:
		return Kind.GLASS
	if atlas == LADDER_ATLAS:
		return Kind.LADDER
	if atlas == CRUMBLE_ATLAS:
		return Kind.CRUMBLE
	if atlas == CRUMBLE_ONE_WAY_ATLAS:
		return Kind.CRUMBLE_ONE_WAY
	var tile_data := layer.get_cell_tile_data(cell)
	if tile_data == null:
		return Kind.EMPTY
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
	if has_solid:
		return Kind.SOLID
	if has_one_way:
		return Kind.ONE_WAY
	return Kind.EMPTY
