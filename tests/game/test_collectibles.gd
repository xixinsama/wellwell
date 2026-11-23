extends Node

const SNAPSHOT := preload("res://addons/platformer_kit/save/save_snapshot.gd")
const ROOM_DATA := preload("res://addons/platformer_kit/world/data/room_data.gd")
const WORLD_DATA := preload("res://addons/platformer_kit/world/data/world_data.gd")
const PICKUP_SCENE := preload("res://scenes/world/number_pickup.tscn")
const SCAN_SCENE_PATH := "user://test_collectible_scan_room.tscn"


func run() -> Array[String]:
	var failures: Array[String] = []
	var registry := get_node_or_null("/root/Collectibles")
	if registry == null:
		return ["Collectibles autoload is missing"]
	registry.call("reset")
	registry.set("current_world_id", "world_a")
	registry.call("register_number", 1)
	registry.call("register_number", 3)
	registry.call("register_number", 5)
	registry.call("collect_number", 3)
	if registry.call("get_known_numbers") != ([1, 3, 5] as Array[int]):
		failures.append("known numbers are wrong: %s" % str(registry.call("get_known_numbers")))
	if int(registry.call("get_total")) != 3 or int(registry.call("get_collected_count")) != 1:
		failures.append("collection totals are wrong")

	# Each world keeps its own numbering.
	registry.call("register_number", 1, "world_b")
	registry.call("collect_number", 2, "world_b")
	if bool(registry.call("is_collected", 3, "world_b")):
		failures.append("world B inherited world A's collection")
	if not bool(registry.call("is_collected", 2, "world_b")):
		failures.append("world B did not store its own number")
	if registry.call("get_known_numbers", "world_b") != ([1, 2] as Array[int]):
		failures.append("world B numbers are wrong: %s" % str(registry.call("get_known_numbers", "world_b")))

	# Round trip through the save snapshot.
	var snapshot: RefCounted = SNAPSHOT.new()
	registry.call("write_to_snapshot", snapshot)
	registry.call("reset")
	if int(registry.call("get_total")) != 0:
		failures.append("reset did not clear the registry")
	registry.call("load_from_snapshot", snapshot)
	if not bool(registry.call("is_collected", 3, "world_a")):
		failures.append("collected numbers did not survive the snapshot")
	if not bool(registry.call("is_collected", 2, "world_b")):
		failures.append("world B's numbers did not survive the snapshot")
	if bool(registry.call("is_collected", 1, "world_a")):
		failures.append("an uncollected number came back collected")

	# Known numbers come back from the scan, not from the save.
	registry.set("current_world_id", "world_a")
	registry.call("register_number", 1)
	registry.call("register_number", 3)
	registry.call("register_number", 5)
	if int(registry.call("get_total")) != 3 or int(registry.call("get_collected_count")) != 1:
		failures.append("rescanning after a load did not restore the totals")
	_assert_scan_discovers_pickups(registry, failures)
	registry.call("reset")
	return failures


## The full set is discovered from the baked rooms, so the screen knows every
## number without extra authoring.
func _assert_scan_discovers_pickups(registry: Node, failures: Array[String]) -> void:
	registry.call("reset")
	var packed := PackedScene.new()
	var root := Node2D.new()
	var pickup := PICKUP_SCENE.instantiate() as Node2D
	pickup.set("number", 4)
	root.add_child(pickup)
	pickup.owner = root
	if packed.pack(root) != OK:
		failures.append("could not pack the scan fixture")
		root.free()
		return
	root.free()
	if ResourceSaver.save(packed, SCAN_SCENE_PATH) != OK:
		failures.append("could not save the scan fixture")
		return
	var room: Resource = ROOM_DATA.new()
	room.set("room_id", "scan_room")
	room.set("scene_path", SCAN_SCENE_PATH)
	var world: Resource = WORLD_DATA.new()
	world.set("world_id", "scan_world")
	world.get("rooms").append(room)
	registry.call("scan_world", world)
	var numbers: Array = registry.call("get_known_numbers")
	if numbers != [4]:
		failures.append("scan_world did not discover the pickup number: %s" % str(numbers))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SCAN_SCENE_PATH))
