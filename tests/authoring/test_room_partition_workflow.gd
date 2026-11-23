extends Node

## End-to-end merge/split workflow against a real world resource.
##
## The importer only accepts worlds under `res://resources/worlds/`, so this test
## builds a throwaway world there and removes it (plus its room outputs) at the
## end. Room sources live in `user://` so no shipped scene is touched.

const WORKFLOW := preload("res://addons/world_editor/authoring/world/room_partition_workflow.gd")
const ROOM_DATA := preload("res://addons/platformer_kit/world/data/room_data.gd")
const WORLD_DATA := preload("res://addons/platformer_kit/world/data/world_data.gd")
const CONNECTION_DATA := preload("res://addons/platformer_kit/world/data/room_connection_data.gd")
const TEMPLATE := preload("res://scenes/rooms/template/level_template.tscn")
const WORLD_ID := "test_partition_world"
const WORLD_PATH := "res://resources/worlds/test_partition_world.tres"
const TERRAIN_PATH := "res://scenes/worlds/test_partition_world/terrain.tscn"
const SOURCE_DIR := "user://partition_"


func run() -> Array[String]:
	var failures: Array[String] = []
	_assert_merge(failures)
	_assert_split(failures)
	_cleanup()
	return failures


func _assert_merge(failures: Array[String]) -> void:
	_cleanup()
	var world := _make_world()
	if world == null:
		failures.append("could not build the partition world fixture")
		return
	var workflow: Object = WORKFLOW.new()
	var ids: Array[String] = ["room_a", "room_b"]
	var merged: Dictionary = workflow.call(
		"merge", world, ids, "merged_room",
		String(workflow.call("source_path_for", world, "merged_room"))
	)
	if not bool(merged.get("ok", false)):
		failures.append("merge failed: %s" % str(merged.get("errors", [])))
		return
	var merged_world := merged.get("world") as WorldData
	if merged_world == null or not merged_world.has_room("merged_room"):
		failures.append("merge did not add the new room")
		return
	if merged_world.has_room("room_a") or merged_world.has_room("room_b"):
		failures.append("merge did not remove the source rooms")
	var rect := Rect2i(merged_world.get_room_origin_chunk("merged_room"), merged_world.get_room("merged_room").room_size_chunks)
	if rect != Rect2i(0, 0, 2, 1):
		failures.append("merged room has the wrong rectangle: %s" % str(rect))
	var connection := merged_world.get_connection("merged_room", "door_a")
	if connection == null:
		failures.append("merge did not remap the room_a connection")
	var reverse := merged_world.get_connection("room_c", "door_c")
	if reverse == null or reverse.to_room_id != "merged_room":
		failures.append("merge did not remap a connection that pointed at the merged room")
	var room := merged_world.get_room("merged_room")
	var source := (load(room.source_scene_path) as PackedScene).instantiate()
	var entities := source.get_node_or_null("RoomContent/Entities")
	if entities == null or entities.get_child_count() != 4:
		failures.append("merged source did not keep both rooms' entities")
	else:
		var spawns: Array[String] = []
		for child: Node in entities.get_children():
			if child.get("spawn_id") != null:
				spawns.append(String(child.get("spawn_id")))
		if not spawns.has("spawn_a") or not spawns.has("spawn_b"):
			failures.append("merged source lost a spawn id: %s" % str(spawns))
	source.free()
	var backup := String(merged.get("backup", ""))
	if backup.is_empty() or not FileAccess.file_exists(backup):
		failures.append("merge did not back up the world resource")


func _assert_split(failures: Array[String]) -> void:
	_cleanup()
	var world := _make_world()
	if world == null:
		failures.append("could not build the partition world fixture")
		return
	var workflow: Object = WORKFLOW.new()
	var new_ids: Array[String] = ["part_a", "part_b"]
	var paths: Array[String] = [
		String(workflow.call("source_path_for", world, "part_a")),
		String(workflow.call("source_path_for", world, "part_b")),
	]
	var split: Dictionary = workflow.call("split", world, "room_wide", "x", 1, new_ids, paths)
	if not bool(split.get("ok", false)):
		failures.append("split failed: %s" % str(split.get("errors", [])))
		return
	var split_world := split.get("world") as WorldData
	if split_world == null or not split_world.has_room("part_a") or not split_world.has_room("part_b"):
		failures.append("split did not add both rooms")
		return
	if split_world.has_room("room_wide"):
		failures.append("split did not remove the original room")
	var left := Rect2i(split_world.get_room_origin_chunk("part_a"), split_world.get_room("part_a").room_size_chunks)
	var right := Rect2i(split_world.get_room_origin_chunk("part_b"), split_world.get_room("part_b").room_size_chunks)
	if left != Rect2i(0, 3, 1, 1) or right != Rect2i(1, 3, 1, 1):
		failures.append("split rooms have the wrong rectangles: %s / %s" % [str(left), str(right)])
	var left_connection := split_world.get_connection("part_a", "door_wide_left")
	if left_connection == null:
		failures.append("split did not map the left entrance to part_a")
	var right_connection := split_world.get_connection("part_b", "door_wide_right")
	if right_connection == null:
		failures.append("split did not map the right entrance to part_b")
	if split_world.start_room_id != "part_a":
		failures.append("split did not move the start room to the side holding the spawn")
	var right_source := (load(split_world.get_room("part_b").source_scene_path) as PackedScene).instantiate()
	var right_entities := right_source.get_node_or_null("RoomContent/Entities")
	var right_entrance_found := false
	if right_entities != null:
		for child: Node in right_entities.get_children():
			var entity_id: Variant = child.get("entity_id")
			if entity_id != null and str(entity_id) == "door_wide_right":
				right_entrance_found = true
				if (child as Node2D).position.x >= 320.0:
					failures.append("split did not re-base the right entrance into its new room")
	if not right_entrance_found:
		failures.append("split did not move the right entrance into part_b")
	right_source.free()


func _make_world() -> WorldData:
	if not _make_source("room_a", "spawn_a", Vector2(16.0, 16.0)):
		return null
	if not _make_source("room_b", "spawn_b", Vector2(16.0, 16.0)):
		return null
	if not _make_source("room_c", "spawn_c", Vector2(16.0, 16.0)):
		return null
	if not _make_wide_source():
		return null
	if not _make_terrain():
		return null
	var world: WorldData = WORLD_DATA.new()
	world.world_id = WORLD_ID
	world.start_room_id = "room_wide"
	world.start_spawn_id = "spawn_left"
	var rooms: Array[Resource] = []
	for entry: Array in [
		["room_a", Vector2i(0, 0), Vector2i.ONE, "spawn_a"],
		["room_b", Vector2i(1, 0), Vector2i.ONE, "spawn_b"],
		["room_c", Vector2i(3, 0), Vector2i.ONE, "spawn_c"],
		["room_wide", Vector2i(0, 3), Vector2i(2, 1), "spawn_left"],
	]:
		var room: RoomData = ROOM_DATA.new()
		room.room_id = String(entry[0])
		room.room_size_chunks = entry[2]
		room.source_scene_path = SOURCE_DIR + String(entry[0]) + ".tscn"
		room.spawn_ids = PackedStringArray([String(entry[3])])
		room.entrance_ids = PackedStringArray(["door_" + String(entry[0]).replace("room_", "")])
		rooms.append(room)
	world.rooms.assign(rooms)
	world.set_room_origin_chunk("room_a", Vector2i(0, 0))
	world.set_room_origin_chunk("room_b", Vector2i(1, 0))
	world.set_room_origin_chunk("room_c", Vector2i(3, 0))
	world.set_room_origin_chunk("room_wide", Vector2i(0, 3))
	var connections: Array[Resource] = []
	for entry: Array in [
		["room_a", "door_a", "room_b", "spawn_b"],
		["room_b", "door_b", "room_a", "spawn_a"],
		["room_c", "door_c", "room_b", "spawn_b"],
		["room_wide", "door_wide_left", "room_a", "spawn_a"],
		["room_wide", "door_wide_right", "room_c", "spawn_c"],
	]:
		var connection: RoomConnectionData = CONNECTION_DATA.new()
		connection.from_room_id = String(entry[0])
		connection.from_entrance_id = String(entry[1])
		connection.to_room_id = String(entry[2])
		connection.to_spawn_id = String(entry[3])
		connections.append(connection)
	world.connections.assign(connections)
	var saved: Error = ResourceSaver.save(world, WORLD_PATH)
	if saved != OK:
		return null
	return ResourceLoader.load(WORLD_PATH, "WorldData", ResourceLoader.CACHE_MODE_IGNORE) as WorldData


## Adds a node to an owned parent without Godot's inconsistent-owner warning.
func _attach(parent: Node, child: Node, scene_root: Node) -> void:
	var previous_owner := parent.owner
	parent.owner = null
	parent.add_child(child)
	parent.owner = previous_owner
	child.owner = scene_root


func _make_source(room_id: String, spawn_id: String, spawn_position: Vector2) -> bool:
	var template := TEMPLATE.instantiate()
	template.set("room_id", room_id)
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
	_attach(entities, spawn, template)
	var entrance: RoomEntrance = RoomEntrance.new()
	entrance.name = "Door"
	entrance.entity_id = "door_" + room_id.replace("room_", "")
	entrance.position = spawn_position + Vector2(8.0, 0.0)
	_attach(entities, entrance, template)
	var scene := PackedScene.new()
	var pack_error := scene.pack(template)
	template.free()
	if pack_error != OK:
		return false
	return ResourceSaver.save(scene, SOURCE_DIR + room_id + ".tscn") == OK


## A 2x1 room with an entrance on each side, for the split test.
func _make_wide_source() -> bool:
	var template := TEMPLATE.instantiate()
	template.set("room_id", "room_wide")
	template.set("room_size_chunks", Vector2i(2, 1))
	var entities := template.get_node_or_null("RoomContent/Entities")
	if entities == null:
		template.free()
		return false
	for child: Node in entities.get_children():
		entities.remove_child(child)
		child.free()
	var spawn: SpawnPoint = SpawnPoint.new()
	spawn.name = "StartSpawn"
	spawn.spawn_id = "spawn_left"
	spawn.position = Vector2(16.0, 16.0)
	_attach(entities, spawn, template)
	for entry: Array in [[Vector2(80.0, 16.0), "door_wide_left"], [Vector2(560.0, 16.0), "door_wide_right"]]:
		var entrance: RoomEntrance = RoomEntrance.new()
		entrance.name = String(entry[1])
		entrance.entity_id = String(entry[1])
		entrance.position = entry[0]
		_attach(entities, entrance, template)
	var scene := PackedScene.new()
	var pack_error := scene.pack(template)
	template.free()
	if pack_error != OK:
		return false
	return ResourceSaver.save(scene, SOURCE_DIR + "room_wide.tscn") == OK


func _make_terrain() -> bool:
	var root := Node2D.new()
	root.name = "WorldTerrain"
	var terrain := Node2D.new()
	terrain.name = "Terrain"
	root.add_child(terrain)
	terrain.owner = root
	var layer := TileMapLayer.new()
	layer.name = "SolidTiles"
	layer.tile_set = load("res://resources/tilesets/primordial_tileset.tres") as TileSet
	terrain.add_child(layer)
	layer.owner = root
	layer.set_cell(Vector2i(0, 0), 0, Vector2i(1, 0))
	var scene := PackedScene.new()
	var pack_error := scene.pack(root)
	root.free()
	if pack_error != OK:
		return false
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TERRAIN_PATH.get_base_dir()))
	return ResourceSaver.save(scene, TERRAIN_PATH) == OK


func _cleanup() -> void:
	for room_id: String in ["room_a", "room_b", "room_c", "room_wide", "merged_room", "part_a", "part_b"]:
		_remove_path(SOURCE_DIR + room_id + ".tscn")
		_remove_path("res://scenes/levels/%s/%s.tscn" % [WORLD_ID, room_id])
		_remove_path("res://resources/rooms/generated/%s.tres" % room_id)
		_remove_directory("res://scenes/rooms/generated/%s" % room_id)
	_remove_path(WORLD_PATH)
	_remove_path(TERRAIN_PATH)
	_remove_directory("res://scenes/worlds/" + WORLD_ID)


func _remove_path(path: String) -> void:
	var absolute := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(absolute):
		DirAccess.remove_absolute(absolute)


func _remove_directory(path: String) -> void:
	var absolute := ProjectSettings.globalize_path(path)
	if not DirAccess.dir_exists_absolute(absolute):
		return
	var directory := DirAccess.open(absolute)
	if directory == null:
		return
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if entry != "." and entry != "..":
			var entry_path := absolute.path_join(entry)
			if directory.current_is_dir():
				_remove_directory(entry_path)
			else:
				DirAccess.remove_absolute(entry_path)
		entry = directory.get_next()
	directory.list_dir_end()
	DirAccess.remove_absolute(absolute)
