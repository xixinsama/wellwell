extends Node

const ROOM_DATA := preload("res://addons/platformer_kit/world/data/room_data.gd")
const WORLD_DATA := preload("res://addons/platformer_kit/world/data/world_data.gd")
const PARTITION := preload("res://addons/world_editor/authoring/world/room_partition_operations.gd")
const TEMPLATE := preload("res://scenes/rooms/template/level_template.tscn")
const SOURCE_A := "user://partition_room_a.tscn"
const SOURCE_B := "user://partition_room_b.tscn"
const MERGED := "user://partition_merged.tscn"
const SPLIT_A := "user://partition_split_a.tscn"
const SPLIT_B := "user://partition_split_b.tscn"
const SPLIT_BIG := "user://partition_room_big.tscn"


func run() -> Array[String]:
	var failures: Array[String] = []
	if not _make_source(SOURCE_A, "spawn_a", Vector2(16, 16)):
		return ["could not build partition fixture A"]
	if not _make_source(SOURCE_B, "spawn_b", Vector2(16, 16)):
		return ["could not build partition fixture B"]
	if not _make_source(SPLIT_BIG, "spawn_big", Vector2(16, 16)):
		return ["could not build partition fixture big"]
	var world := _make_world()
	_assert_rect_geometry(world, failures)
	_assert_merge_sources(world, failures)
	_assert_split_sources(world, failures)
	for path: String in [SOURCE_A, SOURCE_B, SPLIT_BIG, MERGED, SPLIT_A, SPLIT_B]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	return failures


func _make_world() -> WorldData:
	var world: WorldData = WORLD_DATA.new()
	world.world_id = "test_partition"
	var room_a: RoomData = ROOM_DATA.new()
	room_a.room_id = "room_a"
	room_a.room_size_chunks = Vector2i.ONE
	room_a.source_scene_path = SOURCE_A
	var room_b: RoomData = ROOM_DATA.new()
	room_b.room_id = "room_b"
	room_b.room_size_chunks = Vector2i.ONE
	room_b.source_scene_path = SOURCE_B
	var room_big: RoomData = ROOM_DATA.new()
	room_big.room_id = "room_big"
	room_big.room_size_chunks = Vector2i(2, 1)
	room_big.source_scene_path = SPLIT_BIG
	world.rooms.assign([room_a, room_b, room_big])
	world.set_room_origin_chunk("room_a", Vector2i(0, 0))
	world.set_room_origin_chunk("room_b", Vector2i(1, 0))
	world.set_room_origin_chunk("room_big", Vector2i(0, 4))
	return world


func _assert_rect_geometry(world: WorldData, failures: Array[String]) -> void:
	var merge_ids: Array[String] = ["room_a", "room_b"]
	var merged: Dictionary = PARTITION.merge_rect(world, merge_ids)
	if not bool(merged.get("ok", false)) or merged.get("rect") != Rect2i(0, 0, 2, 1):
		failures.append("merge_rect did not return the row union: %s" % str(merged))
	var gap_ids: Array[String] = ["room_a", "room_big"]
	var gap: Dictionary = PARTITION.merge_rect(world, gap_ids)
	if bool(gap.get("ok", false)):
		failures.append("merge_rect accepted a non-rectangular selection")
	var split: Dictionary = PARTITION.split_rects(world, "room_big", "x", 1)
	var rects: Array = split.get("rects", [])
	if not bool(split.get("ok", false)) or rects != [Rect2i(0, 4, 1, 1), Rect2i(1, 4, 1, 1)]:
		failures.append("split_rects returned the wrong halves: %s" % str(split))
	var bad_cut: Dictionary = PARTITION.split_rects(world, "room_big", "x", 0)
	if bool(bad_cut.get("ok", false)):
		failures.append("split_rects accepted a cut on the room edge")


func _assert_merge_sources(world: WorldData, failures: Array[String]) -> void:
	var operations := PARTITION.new() as Object
	var merge_ids: Array[String] = ["room_a", "room_b"]
	var built: Dictionary = operations.call(
		"merge_sources", world, merge_ids, "merged", MERGED
	)
	if not bool(built.get("ok", false)):
		failures.append("merge_sources failed: %s" % str(built.get("errors", [])))
		return
	var source: Node = built["source"]
	if source.get("room_size_chunks") != Vector2i(2, 1):
		failures.append("merged source has the wrong size")
	if source.get("world_origin_chunk") != Vector2i.ZERO:
		failures.append("merged source has the wrong origin")
	var entities := source.get_node_or_null("RoomContent/Entities")
	if entities == null or entities.get_child_count() != 2:
		failures.append("merged source did not keep both rooms' entities")
	source.free()
	var reloaded := (load(MERGED) as PackedScene).instantiate()
	var spawns: Array[String] = []
	for child: Node in reloaded.get_node("RoomContent/Entities").get_children():
		if child.get("spawn_id") != null:
			spawns.append(String(child.get("spawn_id")))
	if spawns != ["spawn_a", "spawn_b"]:
		failures.append("merged source spawn ids are wrong: %s" % str(spawns))
	reloaded.free()


func _assert_split_sources(world: WorldData, failures: Array[String]) -> void:
	var operations := PARTITION.new() as Object
	var paths: Array[String] = [SPLIT_A, SPLIT_B]
	var built: Dictionary = operations.call(
		"split_sources", world, "room_big", "x", 1, paths
	)
	if not bool(built.get("ok", false)):
		failures.append("split_sources failed: %s" % str(built.get("errors", [])))
		return
	var sources: Array = built["sources"]
	if sources.size() != 2:
		failures.append("split_sources did not return two sources")
		for source: Node in sources:
			source.free()
		return
	var left: Node = sources[0]
	var right: Node = sources[1]
	if left.get("room_size_chunks") != Vector2i.ONE or left.get("world_origin_chunk") != Vector2i(0, 4):
		failures.append("left split source has the wrong rect")
	if right.get("room_size_chunks") != Vector2i.ONE or right.get("world_origin_chunk") != Vector2i(1, 4):
		failures.append("right split source has the wrong rect")
	var left_entities := left.get_node_or_null("RoomContent/Entities")
	var right_entities := right.get_node_or_null("RoomContent/Entities")
	if left_entities == null or right_entities == null:
		failures.append("split sources lost their Entities layer")
	left.free()
	right.free()


func _make_source(path: String, spawn_id: String, spawn_position: Vector2) -> bool:
	var template := TEMPLATE.instantiate()
	template.set("room_id", path.get_file().get_basename())
	template.set("room_size_chunks", Vector2i.ONE)
	var entities := template.get_node_or_null("RoomContent/Entities")
	if entities == null:
		template.free()
		return false
	for child: Node in entities.get_children():
		entities.remove_child(child)
		child.free()
	var spawn: SpawnPoint = SpawnPoint.new()
	spawn.name = "StartSpawn"
	spawn.spawn_id = spawn_id
	spawn.position = spawn_position
	entities.add_child(spawn)
	spawn.owner = template
	var scene := PackedScene.new()
	if scene.pack(template) != OK:
		template.free()
		return false
	template.free()
	return ResourceSaver.save(scene, path) == OK
