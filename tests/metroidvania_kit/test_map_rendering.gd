extends Node

const DEFINITION_BUILDER: Script = preload("res://addons/metroidvania_kit/map/data/map_definition_builder.gd")
const MAP_EXPLORATION: Script = preload("res://addons/metroidvania_kit/map/runtime/map_exploration.gd")
const TERRAIN_SNAPSHOT: Script = preload("res://addons/metroidvania_kit/map/data/room_terrain_snapshot.gd")
const PRECISE_RENDERER: Script = preload("res://addons/metroidvania_kit/map/ui/map_precise_renderer.gd")
const GRID_RENDERER: Script = preload("res://addons/metroidvania_kit/map/ui/map_grid_renderer.gd")
const MAP_SCREEN: Script = preload("res://addons/metroidvania_kit/map/ui/map_screen.gd")
const MAP_MINIMAP: Script = preload("res://addons/metroidvania_kit/map/ui/map_minimap.gd")
const EXPLORATION_SOURCE: Script = preload("res://game/map/map_exploration_source.gd")

const TEST_WORLD := "res://resources/worlds/test_world.tres"
const START_TERRAIN := "res://scenes/rooms/generated/test_fog_start/terrain.tscn"


class FakeExplorationSource extends Node:
	var cells: Array[String] = []
	var version := 3

	func get_explored_cells() -> Array[String]:
		return cells.duplicate()

	func get_fog_version() -> int:
		return version


class FakeFogSource extends Node:
	var cells: Array[String] = []
	var version := 2

	func get_explored_cell_ids() -> Array[String]:
		return cells.duplicate()

	func get_exploration_version() -> int:
		return version


func run() -> Array[String]:
	var failures: Array[String] = []
	TERRAIN_SNAPSHOT.clear_cache()
	_assert_definition_follows_world(failures)
	_assert_snapshot_reads_terrain(failures)
	_assert_exploration_maps_cells(failures)
	_assert_precise_image_filters_unexplored(failures)
	_assert_grid_ratio(failures)
	_assert_exploration_source_merges(failures)
	_assert_player_marker_scales(failures)
	_assert_map_screen_and_minimap_build(failures)
	return failures


func _assert_definition_follows_world(failures: Array[String]) -> void:
	var world: Resource = load(TEST_WORLD)
	var definition: Resource = DEFINITION_BUILDER.from_world(world)
	if definition == null:
		failures.append("map definition could not be built from the test world")
		return
	var room_ids: Array = definition.call("get_room_ids")
	if room_ids.size() != world.get_room_ids().size():
		failures.append("map definition lost rooms from the world")
	var start: Resource = definition.call("get_room", &"test_fog_start")
	var wide: Resource = definition.call("get_room", &"test_fog_wide")
	if start == null or wide == null:
		failures.append("map definition lost a test room")
		return
	if Vector2i(start.get("map_position")) != world.get_room_origin_chunk("test_fog_start"):
		failures.append("start room map position did not follow its world placement")
	if Vector2i(wide.get("map_position")) != world.get_room_origin_chunk("test_fog_wide"):
		failures.append("wide room map position did not follow its world placement")
	if Vector2i(wide.get("map_size")) != world.get_room("test_fog_wide").room_size_chunks:
		failures.append("wide room map size did not follow its chunk size")
	var expected_links := 0
	for connection: Resource in world.get("connections"):
		if world.has_room(connection.from_room_id) and world.has_room(connection.to_room_id):
			expected_links += 1
	if (definition.get("connections") as Array).size() != expected_links:
		failures.append("map definition did not turn world connections into map links")
	var metadata: Dictionary = start.get("metadata")
	if String(metadata.get("terrain_scene_path", "")).is_empty():
		failures.append("map room did not remember its terrain scene path")


func _assert_snapshot_reads_terrain(failures: Array[String]) -> void:
	var snapshot: Dictionary = TERRAIN_SNAPSHOT.get_snapshot(START_TERRAIN)
	var cells: Dictionary = snapshot.get("cells", {})
	if cells.is_empty():
		failures.append("terrain snapshot found no cells")
		return
	if snapshot.get("size") != Vector2i(40, 23):
		failures.append("terrain snapshot size was not the room cell size")
	_expect_kind(cells, Vector2i(0, 0), TERRAIN_SNAPSHOT.Kind.SOLID, "wall", failures)
	_expect_kind(cells, Vector2i(4, 4), TERRAIN_SNAPSHOT.Kind.GLASS, "glass", failures)
	_expect_kind(cells, Vector2i(7, 15), TERRAIN_SNAPSHOT.Kind.LADDER, "ladder", failures)
	_expect_kind(cells, Vector2i(20, 17), TERRAIN_SNAPSHOT.Kind.CRUMBLE_ONE_WAY, "crumble one-way", failures)
	_expect_kind(cells, Vector2i(28, 16), TERRAIN_SNAPSHOT.Kind.CRUMBLE, "crumble", failures)
	var again: Dictionary = TERRAIN_SNAPSHOT.get_snapshot(START_TERRAIN)
	if int(again.get("version")) != int(snapshot.get("version")):
		failures.append("terrain snapshot was rescanned even though the file did not change")


func _assert_exploration_maps_cells(failures: Array[String]) -> void:
	var definition: Resource = DEFINITION_BUILDER.from_world(load(TEST_WORLD))
	var exploration: MapExploration = MAP_EXPLORATION.new()
	var ids: Array[String] = []
	for x in range(4):
		for y in range(2):
			ids.append("test_fog_start:%d,%d" % [x, y])
	# The wide room starts at chunk 1: global x 40 is its local x 0.
	ids.append("test_fog_wide:41,5")
	exploration.refresh(ids, definition)
	if not exploration.has_any("test_fog_start"):
		failures.append("exploration did not collect start room cells")
	if exploration.cells_for("test_fog_start").size() != 8:
		failures.append("exploration cell count was wrong")
	if not exploration.cells_for("test_fog_wide").has(Vector2i(1, 5)):
		failures.append("exploration did not convert global cells into room-local cells")
	var ratio := exploration.ratio("test_fog_wide", definition)
	var expected := 1.0 / float(80 * 23)
	if absf(ratio - expected) > 0.0001:
		failures.append("exploration ratio did not use the room area")
	if exploration.ratio("test_fog_start", definition) <= 0.0:
		failures.append("exploration ratio stayed zero for a visited room")


func _assert_precise_image_filters_unexplored(failures: Array[String]) -> void:
	var definition: Resource = DEFINITION_BUILDER.from_world(load(TEST_WORLD))
	var room: Resource = definition.call("get_room", &"test_fog_start")
	var exploration: MapExploration = MAP_EXPLORATION.new()
	var ids: Array[String] = ["test_fog_start:0,0", "test_fog_start:4,4"]
	exploration.refresh(ids, definition)
	var renderer: Control = PRECISE_RENDERER.new()
	renderer.bind(definition, exploration)
	var image: Image = renderer.call("build_room_image", room)
	if image == null:
		failures.append("precise renderer did not build a room image")
		renderer.free()
		return
	if image.get_size() != Vector2i(40, 23):
		failures.append("precise room image did not use one pixel per cell")
	if not _colors_close(image.get_pixel(0, 0), PRECISE_RENDERER.COLOR_SOLID):
		failures.append("explored wall cell was not painted as solid")
	if not _colors_close(image.get_pixel(4, 4), PRECISE_RENDERER.COLOR_GLASS):
		failures.append("explored glass cell was not painted as glass")
	if not _colors_close(image.get_pixel(30, 20), PRECISE_RENDERER.COLOR_UNEXPLORED):
		failures.append("unexplored cell was not painted as unexplored")
	var empty: MapExploration = MAP_EXPLORATION.new()
	empty.refresh([], definition)
	renderer.bind(definition, empty)
	var blank: Image = renderer.call("build_room_image", room)
	if blank.get_pixel(0, 0).a != 1.0:
		failures.append("unvisited room image was not an opaque black silhouette")
	renderer.free()


func _assert_grid_ratio(failures: Array[String]) -> void:
	var definition: Resource = DEFINITION_BUILDER.from_world(load(TEST_WORLD))
	var exploration: MapExploration = MAP_EXPLORATION.new()
	var ids: Array[String] = []
	for x in range(40):
		for y in range(23):
			ids.append("test_fog_start:%d,%d" % [x, y])
	exploration.refresh(ids, definition)
	var renderer: Control = GRID_RENDERER.new()
	renderer.bind(definition, exploration)
	if renderer.get("definition") != definition:
		failures.append("grid renderer did not keep its definition")
	if exploration.ratio("test_fog_start", definition) != 1.0:
		failures.append("fully explored room did not reach a 100% ratio")
	if exploration.ratio("test_fog_wide", definition) != 0.0:
		failures.append("unvisited room did not stay at a 0% ratio")
	renderer.free()


func _assert_exploration_source_merges(failures: Array[String]) -> void:
	var bridge := FakeExplorationSource.new()
	bridge.cells = ["test_fog_start:1,1", "test_fog_wide:40,1"]
	var fog := FakeFogSource.new()
	fog.cells = ["test_fog_start:1,1", "test_fog_start:2,1"]
	var source: MapExplorationSource = EXPLORATION_SOURCE.new()
	source.bridge = bridge
	source.fog = fog
	var merged: Array[String] = source.get_explored_cells()
	if merged.size() != 3:
		failures.append("exploration source did not merge fog and saved cells without duplicates")
	if not merged.has("test_fog_wide:40,1"):
		failures.append("exploration source dropped a saved room cell")
	if source.get_fog_version() == 0:
		failures.append("exploration source did not expose a change version")
	bridge.free()
	fog.free()


func _assert_player_marker_scales(failures: Array[String]) -> void:
	var precise: Control = PRECISE_RENDERER.new()
	precise.set_zoom(1.0)
	if precise.call("player_marker_pixels") != 3.0:
		failures.append("player marker was not the minimum size at 1x zoom")
	precise.set_zoom(2.0)
	if precise.call("player_marker_pixels") != 3.0:
		failures.append("player marker grew before 2x zoom")
	precise.set_zoom(4.0)
	if precise.call("player_marker_pixels") != 6.0:
		failures.append("player marker did not follow the map between 2x and 4x")
	precise.set_zoom(8.0)
	if precise.call("player_marker_pixels") != 12.0:
		failures.append("player marker did not keep growing past 4x")
	precise.free()
	var grid: Control = GRID_RENDERER.new()
	grid.set_zoom(1.0)
	if grid.call("player_marker_pixels") != 3.0:
		failures.append("grid player marker was not the minimum size at 1x zoom")
	grid.set_zoom(2.0)
	if grid.call("player_marker_pixels") != 3.0:
		failures.append("grid player marker grew before 2x zoom")
	grid.set_zoom(4.0)
	if grid.call("player_marker_pixels") != 6.0:
		failures.append("grid player marker did not follow the map zoom")
	grid.free()


func _assert_map_screen_and_minimap_build(failures: Array[String]) -> void:
	var screen: Control = MAP_SCREEN.new()
	add_child(screen)
	if screen.find_child("Dim", true, false) == null:
		failures.append("map screen did not build its frame")
	if screen.find_child("PreciseMap", true, false) == null:
		failures.append("map screen did not build the precise renderer")
	if screen.find_child("GridMap", true, false) == null:
		failures.append("map screen did not build the grid renderer")
	screen.call("set_style", "grid")
	if screen.call("get_style") != "grid":
		failures.append("map screen did not switch style")
	if not (screen.find_child("GridMap", true, false) as Control).visible:
		failures.append("grid style did not show the grid renderer")
	screen.queue_free()
	var minimap: Control = MAP_MINIMAP.new()
	add_child(minimap)
	if minimap.find_child("GridMap", true, false) == null:
		failures.append("minimap did not build its renderers")
	minimap.queue_free()


func _expect_kind(cells: Dictionary, cell: Vector2i, kind: int, label: String, failures: Array[String]) -> void:
	if int(cells.get(cell, -1)) != kind:
		failures.append("terrain snapshot classified %s at %s as %s" % [label, cell, cells.get(cell, -1)])


func _colors_close(left: Color, right: Color) -> bool:
	var tolerance := 0.01
	return (
		absf(left.r - right.r) <= tolerance
		and absf(left.g - right.g) <= tolerance
		and absf(left.b - right.b) <= tolerance
		and absf(left.a - right.a) <= tolerance
	)
