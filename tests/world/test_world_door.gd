extends Node

const DOOR_SCENE := "res://addons/platformer_kit/world/entities/world_door.tscn"
const SAVE_SNAPSHOT := preload("res://addons/platformer_kit/save/save_snapshot.gd")
const WORLD_DATA := preload("res://addons/platformer_kit/world/data/world_data.gd")


class FakePortalHost extends Node2D:
	var calls: Array = []
	func travel_to_door(room_id: String, door_id: String) -> bool:
		calls.append([room_id, door_id])
		return true


class FakeShuttleHost extends Node2D:
	var calls: Array = []
	func travel_to_world(world: Resource, room_id: String, door_id: String) -> bool:
		calls.append([world.world_id if world != null else "", room_id, door_id])
		return true


func run() -> Array[String]:
	var failures: Array[String] = []
	if not ResourceLoader.exists(DOOR_SCENE, "PackedScene"):
		return ["WorldDoor scene is missing: %s" % DOOR_SCENE]
	_assert_scene_contract(failures)
	_assert_default_arrival_clears_activation_area(failures)
	_assert_activation_persists_and_saves(failures)
	_assert_unlinked_door_refuses_to_travel(failures)
	_assert_portal_dispatch(failures)
	_assert_shuttle_dispatch(failures)
	_assert_arrival_disarm_rearms_after_exit(failures)
	return failures


func _assert_scene_contract(failures: Array[String]) -> void:
	var door := _make_door({"entity_id": "portal_a"})
	if door == null:
		failures.append("WorldDoor scene could not be instantiated")
		return
	for path: String in ["ActivationArea/CollisionShape2D", "Interactable/CollisionShape2D", "ArrivalSpawn"]:
		if door.get_node_or_null(path) == null:
			failures.append("WorldDoor scene is missing %s" % path)
	var area := door.get_node("ActivationArea") as Area2D
	if area.collision_layer != 0 or area.collision_mask != 2:
		failures.append("WorldDoor activation area does not detect the player collision layer")
	var arrival := door.get_node("ArrivalSpawn")
	if String(arrival.get("spawn_id")) != "portal_a":
		failures.append("WorldDoor arrival spawn does not answer to the door entity_id")
	if not door.get("persistent"):
		failures.append("WorldDoor is not a persistent entity")
	if door.get("entity_type") != "world_door":
		failures.append("WorldDoor does not declare its entity type")
	door.get_parent().free()


## The arrival point must not sit inside the door's own sensor, or the actor
## arrives standing in the door and the pair sends it straight back.
func _assert_default_arrival_clears_activation_area(failures: Array[String]) -> void:
	var door := _make_door({"entity_id": "portal_a"})
	if door == null:
		return
	var area_node := door.get_node("ActivationArea/CollisionShape2D") as CollisionShape2D
	var area_rect := (area_node.shape as RectangleShape2D).get_rect()
	area_rect.position += area_node.position
	var arrival := (door.get_node("ArrivalSpawn") as Node2D).position
	# The actor body is 6x6 and centred 3px above its origin.
	var player_half := Vector2(3, 3)
	var clearance := Rect2(
		arrival - player_half - Vector2(0.0, 6.0),
		player_half * 2.0
	)
	if clearance.intersects(area_rect):
		failures.append("WorldDoor default arrival spawn overlaps its activation area")
	door.get_parent().free()


func _assert_activation_persists_and_saves(failures: Array[String]) -> void:
	var snapshot: RefCounted = SAVE_SNAPSHOT.new()
	var host := FakePortalHost.new()
	add_child(host)
	var door := _make_door({
		"entity_id": "portal_a",
		"target_room_id": "room_b",
		"target_door_id": "portal_b",
	}, host, snapshot)
	if door == null:
		host.free()
		return
	var requests: Array[bool] = []
	door.save_requested.connect(func(immediate: bool) -> void: requests.append(immediate))
	if not bool(door.call("activate", null)):
		failures.append("WorldDoor refused a configured portal activation")
	if not bool(door.get("activated")):
		failures.append("WorldDoor did not activate")
	if not bool(snapshot.get_entity_state("world_a:room_a:portal_a").get("activated", false)):
		failures.append("WorldDoor did not persist its activated state")
	if requests != [false]:
		failures.append("WorldDoor did not queue exactly one deferred save")
	if host.calls != [["room_b", "portal_b"]]:
		failures.append("WorldDoor did not ask its host to travel to the partner door")
	if bool(door.call("activate", null)):
		failures.append("WorldDoor travelled twice without leaving the door")
	host.free()


func _assert_unlinked_door_refuses_to_travel(failures: Array[String]) -> void:
	var snapshot: RefCounted = SAVE_SNAPSHOT.new()
	var host := FakePortalHost.new()
	add_child(host)
	var door := _make_door({"entity_id": "orphan"}, host, snapshot)
	if door == null:
		host.free()
		return
	if bool(door.call("activate", null)):
		failures.append("WorldDoor activated without a configured link")
	if not host.calls.is_empty() or bool(door.get("activated")):
		failures.append("WorldDoor mutated state for an unlinked activation")
	host.free()


func _assert_portal_dispatch(failures: Array[String]) -> void:
	var snapshot: RefCounted = SAVE_SNAPSHOT.new()
	var host := FakePortalHost.new()
	add_child(host)
	var door := _make_door({
		"entity_id": "portal_a",
		"door_kind": 0,
		"target_room_id": "room_b",
		"target_door_id": "portal_b",
	}, host, snapshot)
	if door == null:
		host.free()
		return
	if not bool(door.call("activate", null)):
		failures.append("PORTAL door did not travel")
	if host.calls.size() != 1:
		failures.append("PORTAL door did not use the in-world travel path")
	host.free()


func _assert_shuttle_dispatch(failures: Array[String]) -> void:
	var snapshot: RefCounted = SAVE_SNAPSHOT.new()
	var host := FakeShuttleHost.new()
	add_child(host)
	var other_world: Resource = WORLD_DATA.new()
	other_world.world_id = "world_b"
	var door := _make_door({
		"entity_id": "shuttle_a",
		"door_kind": 1,
		"target_world": other_world,
		"target_room_id": "room_b",
		"target_door_id": "shuttle_b",
	}, host, snapshot)
	if door == null:
		host.free()
		return
	if String(door.call("get_target_world_id")) != "world_b":
		failures.append("SHUTTLE door does not expose its target world id")
	if not bool(door.call("activate", null)):
		failures.append("SHUTTLE door did not travel")
	if host.calls != [["world_b", "room_b", "shuttle_b"]]:
		failures.append("SHUTTLE door did not use the cross-world travel path")
	host.free()


func _assert_arrival_disarm_rearms_after_exit(failures: Array[String]) -> void:
	var snapshot: RefCounted = SAVE_SNAPSHOT.new()
	var host := FakePortalHost.new()
	add_child(host)
	var door := _make_door({
		"entity_id": "portal_a",
		"target_room_id": "room_b",
		"target_door_id": "portal_b",
	}, host, snapshot)
	if door == null:
		host.free()
		return
	door.call("set_arrival_disarmed")
	if bool(door.call("is_armed")) or bool(door.call("activate", null)):
		failures.append("disarmed arrival door still travelled")
	for _index: int in range(WorldDoor.REARM_FRAMES + 1):
		door.call("_physics_process", 0.016)
	if not bool(door.call("is_armed")):
		failures.append("arrival door did not re-arm after the actor stepped out")
	if not bool(door.call("activate", null)):
		failures.append("re-armed arrival door refused a new trip")
	host.free()


func _make_door(values: Dictionary, host: Node = null, snapshot: RefCounted = null) -> Node:
	var packed := load(DOOR_SCENE) as PackedScene
	if packed == null:
		return null
	var door := packed.instantiate()
	for key: String in values:
		door.set(key, values[key])
	var parent: Node = host
	if parent == null:
		parent = Node2D.new()
		add_child(parent)
	parent.add_child(door)
	door.set("persistent", true)
	door.call("setup_entity", {
		"world_id": "world_a",
		"room_id": "room_a",
		"entity_state_sink": snapshot if snapshot != null else SAVE_SNAPSHOT.new(),
	})
	return door
