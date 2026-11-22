extends SceneTree

## One-time migration to the world-centric terrain model.
##
## For every world: merge each room source's Terrain cells into the world's
## single terrain scene (`scenes/worlds/<world_id>/terrain.tscn`), then clear the
## room source Terrain cells (the layers stay, so the authoring contract and the
## room scene structure are unchanged). Backups of every modified scene go to
## `res://resources/worlds/_migration_backup/<timestamp>/`.
##
## Usage:
##   godot --headless --path . -s res://tools/migrate_world_terrain.gd -- --dry-run
##   godot --headless --path . -s res://tools/migrate_world_terrain.gd
##   godot --headless --path . -s res://tools/migrate_world_terrain.gd -- --world=res://resources/worlds/dash_world.tres --force

const WORLD_DIR := "res://resources/worlds/"
const TERRAIN_TEMPLATE := "res://scenes/worlds/terrain_template.tscn"
const BACKUP_DIR := "res://resources/worlds/_migration_backup/"
const TILE_LAYER_NAMES: Array[String] = [
	"BackTiles", "SolidTiles", "DetailTiles", "GlassTiles",
	"VisionBlockTiles", "MarkerTiles", "CrumbleTiles", "CrumbleOneWayTiles",
]

var _dry_run := false
var _force := false
var _only_world := ""
var _timestamp := ""
var _sources: Dictionary[String, bool] = {}
var _errors := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument == "--dry-run":
			_dry_run = true
		elif argument == "--force":
			_force = true
		elif argument.begins_with("--world="):
			_only_world = argument.trim_prefix("--world=")
	_timestamp = Time.get_datetime_string_from_system().replace(":", "-")
	var world_paths := _world_paths()
	print("migrate: %d world(s), dry_run=%s, force=%s" % [world_paths.size(), _dry_run, _force])
	for path: String in world_paths:
		_migrate_world(path)
	if not _dry_run:
		_clear_sources()
	print("migrate: done, sources=%d, errors=%d, backup=%s" % [_sources.size(), _errors, _backup_root()])
	quit(0 if _errors == 0 else 1)


func _world_paths() -> Array[String]:
	var result: Array[String] = []
	if not _only_world.is_empty():
		result.append(_only_world)
		return result
	var directory := DirAccess.open(WORLD_DIR)
	if directory == null:
		return result
	for file_name: String in directory.get_files():
		if not file_name.ends_with(".tres"):
			continue
		if file_name.ends_with("_stack.tres") or file_name == "world_catalog.tres":
			continue
		result.append(WORLD_DIR + file_name)
	result.sort()
	return result


func _migrate_world(world_path: String) -> void:
	var world := ResourceLoader.load(world_path, "WorldData", ResourceLoader.CACHE_MODE_IGNORE) as WorldData
	if world == null:
		print("  skip (not WorldData): ", world_path)
		return
	var terrain_path := world.get_terrain_scene_path()
	if terrain_path.is_empty():
		print("  skip (no terrain path): ", world_path)
		return
	print("world ", world.world_id, " -> ", terrain_path)
	var merged: Dictionary = {}
	var layer_tile_set: TileSet
	var conflicts := 0
	for room_id: String in world.get_room_ids():
		var room: RoomData = world.get_room(room_id)
		if room == null or room.source_scene_path.is_empty():
			continue
		if not ResourceLoader.exists(room.source_scene_path, "PackedScene"):
			_warn("missing room source: %s" % room.source_scene_path)
			continue
		var cell_origin: Vector2i = world.get_room_cell_rect(room_id).position
		var source := _load_scene(room.source_scene_path)
		var terrain := source.get_node_or_null("RoomContent/Terrain")
		if terrain == null:
			source.free()
			continue
		var layers: Array[TileMapLayer] = []
		_collect_layers(terrain, layers)
		for layer: TileMapLayer in layers:
			if layer.tile_set != null and layer_tile_set == null:
				layer_tile_set = layer.tile_set
			var target_name := String(layer.name)
			var target: Dictionary = merged.get(target_name, {})
			for cell: Vector2i in layer.get_used_cells():
				var world_cell := cell_origin + cell
				var tile := [
					layer.get_cell_source_id(cell),
					layer.get_cell_atlas_coords(cell),
					layer.get_cell_alternative_tile(cell),
				]
				if target.has(world_cell) and target[world_cell] != tile:
					conflicts += 1
				target[world_cell] = tile
			merged[target_name] = target
		source.free()
		_sources[room.source_scene_path] = true
	if merged.is_empty():
		print("  no terrain cells to merge")
		return
	if FileAccess.file_exists(terrain_path) and not _force:
		print("  terrain scene already exists, skipping (use --force): ", terrain_path)
		return
	if _dry_run:
		var total := 0
		for cells: Dictionary in merged.values():
			total += cells.size()
		print("  would write %d cell(s) across %d layer(s), conflicts=%d" % [total, merged.size(), conflicts])
		return
	if _write_world_terrain(terrain_path, merged, layer_tile_set):
		print("  wrote ", terrain_path)


func _write_world_terrain(path: String, merged: Dictionary, tile_set: TileSet) -> bool:
	var template := _load_scene(TERRAIN_TEMPLATE)
	if template == null:
		_warn("terrain template missing")
		return false
	var layers: Array[TileMapLayer] = []
	_collect_layers(template, layers)
	var by_name: Dictionary = {}
	for layer: TileMapLayer in layers:
		by_name[String(layer.name)] = layer
		for layer_name: Variant in merged:
			if String(layer_name) == String(layer.name):
				continue
	for layer_name: String in merged:
		var layer: TileMapLayer = by_name.get(layer_name, null)
		if layer == null:
			layer = TileMapLayer.new()
			layer.name = layer_name
			template.add_child(layer)
			by_name[layer_name] = layer
		if layer.tile_set == null:
			layer.tile_set = tile_set
		var cells: Dictionary = merged[layer_name]
		for world_cell: Vector2i in cells:
			var tile: Array = cells[world_cell]
			layer.set_cell(world_cell, int(tile[0]), Vector2i(tile[1]), int(tile[2]))
	var scene := PackedScene.new()
	var pack_error := scene.pack(template)
	if pack_error != OK:
		template.free()
		_warn("could not pack world terrain")
		return false
	template.free()
	var dir_error := DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(path.get_base_dir())
	)
	if dir_error != OK and dir_error != ERR_ALREADY_EXISTS:
		_warn("could not create %s" % path.get_base_dir())
		return false
	if ResourceSaver.save(scene, path) != OK:
		_warn("could not save %s" % path)
		return false
	return true


func _clear_sources() -> void:
	for source_path: String in _sources:
		if _is_inherited(source_path):
			print("  note: inherited scene, clear its Terrain manually: ", source_path)
			continue
		var instance := _load_scene(source_path)
		if instance == null:
			continue
		var terrain := instance.get_node_or_null("RoomContent/Terrain")
		if terrain == null:
			instance.free()
			continue
		var layers: Array[TileMapLayer] = []
		_collect_layers(terrain, layers)
		var cells := 0
		for layer: TileMapLayer in layers:
			cells += layer.get_used_cells().size()
			layer.clear()
		if cells == 0:
			instance.free()
			continue
		_backup(source_path)
		var scene := PackedScene.new()
		if scene.pack(instance) != OK:
			_warn("could not pack %s" % source_path)
			instance.free()
			continue
		instance.free()
		if ResourceSaver.save(scene, source_path) != OK:
			_warn("could not save %s" % source_path)
		else:
			print("  cleared %d terrain cell(s) in %s" % [cells, source_path])


func _load_scene(path: String) -> Node:
	var packed := ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if packed == null:
		return null
	return packed.instantiate()


## Re-saving an inherited scene instance would flatten it, so those sources keep
## their Terrain cells and only get the "clear manually" note. The bake ignores
## room terrain anyway.
func _is_inherited(path: String) -> bool:
	var packed := ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if packed == null:
		return false
	var state := packed.get_state()
	return state != null and state.get_base_scene_state() != null


func _collect_layers(node: Node, layers: Array[TileMapLayer]) -> void:
	if node is TileMapLayer:
		layers.append(node as TileMapLayer)
	for child: Node in node.get_children():
		_collect_layers(child, layers)


func _backup(path: String) -> void:
	var relative := path.trim_prefix("res://")
	var target := _backup_root() + relative
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(target.get_base_dir()))
	if DirAccess.copy_absolute(
		ProjectSettings.globalize_path(path),
		ProjectSettings.globalize_path(target)
	) != OK:
		_warn("could not back up %s" % path)


func _backup_root() -> String:
	return BACKUP_DIR + _timestamp + "/"


func _warn(message: String) -> void:
	_errors += 1
	push_warning("migrate: " + message)
	print("  ERROR: ", message)
