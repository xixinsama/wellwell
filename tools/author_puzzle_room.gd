extends SceneTree

## Bakes the authored room_04_00 source scene and registers it in the_world.tres.
##
## Edit res://scenes/levels/room_04_00.tscn in the Godot editor first, then run:
##   godot --headless --path . -s res://tools/author_puzzle_room.gd
##
## The source scene stays the single source of truth; this tool never rewrites
## it. Generated runtime/terrain scenes and RoomData are bake outputs.

const ROOM_BAKER := preload("res://addons/world_editor/authoring/room/room_baker.gd")
const ROOM_PLACEMENT := preload("res://addons/platformer_kit/world/data/world_room_placement_data.gd")

const ROOM_ID := "room_04_00"
const SOURCE_PATH := "res://scenes/levels/room_04_00.tscn"
const WORLD_PATH := "res://resources/worlds/the_world.tres"
const ROOM_RESOURCE_PATH := "res://resources/rooms/generated/room_04_00.tres"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []

	if not _bake_source(failures):
		failures.append("could not bake room source")

	if not _register_world(failures):
		failures.append("could not register room in world data")

	for failure: String in failures:
		push_error("author_puzzle_room: %s" % failure)
	print("author_puzzle_room: done with %d failure(s)" % failures.size())
	quit(1 if not failures.is_empty() else 0)


func _bake_source(failures: Array[String]) -> bool:
	if not ResourceLoader.exists(SOURCE_PATH, "PackedScene"):
		failures.append("source scene is missing: %s" % SOURCE_PATH)
		return false
	var source_root: Node = (load(SOURCE_PATH) as PackedScene).instantiate()
	if source_root == null:
		failures.append("could not instantiate source scene")
		return false
	var baker: RefCounted = ROOM_BAKER.new()
	var bake_result: Dictionary = baker.bake(source_root, SOURCE_PATH)
	source_root.free()
	if not bake_result.get("ok", false):
		failures.append("bake failed: %s" % bake_result.get("errors", []))
		return false
	return true


func _register_world(failures: Array[String]) -> bool:
	var room_data: Resource = ResourceLoader.load(
		ROOM_RESOURCE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE
	)
	if room_data == null:
		failures.append("generated RoomData missing at %s" % ROOM_RESOURCE_PATH)
		return false
	var world := load(WORLD_PATH) as WorldData
	if world == null:
		failures.append("could not load world data")
		return false
	if world.has_room(ROOM_ID):
		return true

	world.rooms.append(room_data)
	var placement: Resource = ROOM_PLACEMENT.new()
	placement.room_id = ROOM_ID
	placement.origin_chunk = Vector2i(4, 0)
	world.placements.append(placement)
	world.sort_for_serialization()
	var save_err := ResourceSaver.save(world, WORLD_PATH)
	if save_err != OK:
		failures.append("save world data error: %s" % save_err)
		return false
	return true
