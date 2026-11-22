extends Node

## The components gallery is a copy source, so every station it advertises must
## keep its components, its one-way flag and the phantom wall's erased terrain.
## The room is also registered in the test world, which this guards as well.

const GALLERY_PATH := "res://scenes/levels/test/components_gallery.tscn"
const WORLD_PATH := "res://resources/worlds/test_world.tres"
const ROOM_CONTRACT := preload("res://addons/world_editor/authoring/room/room_authoring_contract.gd")
const ROOM_ID := "components_gallery"
const ROOM_ORIGIN := Vector2i(3, 1)
const PHANTOM_CELL := Vector2i(60, 18)


func run() -> Array[String]:
	var failures: Array[String] = []
	var packed := load(GALLERY_PATH) as PackedScene
	if packed == null:
		return ["components gallery scene is missing: %s" % GALLERY_PATH]
	var room: Node = packed.instantiate()
	var validation: Dictionary = ROOM_CONTRACT.validate(room)
	for error: String in validation.get("errors", []):
		failures.append("components gallery room contract: %s" % error)
	if room.get("room_size_chunks") != Vector2i(2, 1):
		failures.append("components gallery is not a two-chunk room")
	var entities := room.get_node_or_null("RoomContent/Entities")
	if entities == null:
		room.free()
		return failures + ["components gallery has no RoomContent/Entities"]
	_assert_elevator(entities, failures)
	_assert_conveyor(entities, failures)
	_assert_waypoint(entities, failures)
	_assert_falling(entities, failures)
	_assert_one_way(entities, failures)
	_assert_door(entities, failures)
	_assert_phantom_wall(room, entities, failures)
	_assert_signs(entities, failures)
	_assert_world_registration(failures)
	room.free()
	return failures


func _assert_elevator(entities: Node, failures: Array[String]) -> void:
	var platform := entities.get_node_or_null("01_Elevator") as AnimatableBody2D
	if platform == null:
		failures.append("01_Elevator is missing its AnimatableBody2D")
		return
	var motion := platform.get_node_or_null("ElevatorMotion")
	if motion == null or not motion.has_method("activate"):
		failures.append("01_Elevator has no ElevatorMotionComponent2D")
	if platform.get_node_or_null("RiderTrigger") == null:
		failures.append("01_Elevator has no RiderTrigger")
	if platform.get_node_or_null("CollisionShape2D") == null:
		failures.append("01_Elevator has no collision shape")


func _assert_conveyor(entities: Node, failures: Array[String]) -> void:
	var platform := entities.get_node_or_null("02_Conveyor") as AnimatableBody2D
	if platform == null:
		failures.append("02_Conveyor is missing its AnimatableBody2D")
		return
	var surface := platform.get_node_or_null("ConveyorSurface")
	if surface == null or Vector2(surface.get("surface_velocity")) == Vector2.ZERO:
		failures.append("02_Conveyor has no moving ConveyorSurface")


func _assert_waypoint(entities: Node, failures: Array[String]) -> void:
	var platform := entities.get_node_or_null("03_Waypoint") as AnimatableBody2D
	if platform == null:
		failures.append("03_Waypoint is missing its AnimatableBody2D")
		return
	var motion := platform.get_node_or_null("WaypointMotion")
	if motion == null or not motion.has_method("is_route_valid"):
		failures.append("03_Waypoint has no WaypointMotionComponent2D")
	elif not bool(motion.call("is_route_valid")):
		failures.append("03_Waypoint route is invalid (waypoints must start at zero)")
	var occluder := platform.get_node_or_null("FogOccluder")
	if occluder == null or not occluder.has_method("is_occluding"):
		failures.append("03_Waypoint has no FogOccluderComponent2D")
	elif occluder.call("get_world_rect") != Rect2(platform.position, Vector2(24.0, 8.0)):
		failures.append("03_Waypoint occluder does not follow its collision shape")


func _assert_falling(entities: Node, failures: Array[String]) -> void:
	var platform := entities.get_node_or_null("04_Falling") as AnimatableBody2D
	if platform == null:
		failures.append("04_Falling is missing its AnimatableBody2D")
		return
	var motion := platform.get_node_or_null("FallMotion")
	if motion == null or not motion.has_method("activate"):
		failures.append("04_Falling has no FallMotionComponent2D")
	if platform.get_node_or_null("RiderTrigger") == null:
		failures.append("04_Falling has no RiderTrigger")


func _assert_one_way(entities: Node, failures: Array[String]) -> void:
	var platform := entities.get_node_or_null("07_OneWayPlatform") as StaticBody2D
	if platform == null:
		failures.append("07_OneWayPlatform is missing its StaticBody2D")
		return
	var shape := platform.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape == null or not shape.one_way_collision:
		failures.append("07_OneWayPlatform does not set CollisionShape2D.one_way_collision")


func _assert_door(entities: Node, failures: Array[String]) -> void:
	var door := entities.get_node_or_null("05_Door") as Node2D
	if door == null:
		failures.append("05_Door is missing")
		return
	var component := door.get_node_or_null("Door")
	if component == null or not component.has_method("is_closed"):
		failures.append("05_Door has no DoorComponent2D")
	var occluder := door.get_node_or_null("FogOccluder")
	if occluder == null or not bool(occluder.call("is_occluding")):
		failures.append("05_Door does not start as a sight blocker")
	if door.get_node_or_null("Sense") == null:
		failures.append("05_Door has no sense area")


func _assert_phantom_wall(room: Node, entities: Node, failures: Array[String]) -> void:
	var wall := entities.get_node_or_null("06_PhantomWall") as TileMapLayer
	if wall == null:
		failures.append("06_PhantomWall is missing its TileMapLayer")
		return
	if wall.collision_enabled:
		failures.append("06_PhantomWall must have collision disabled")
	if wall.get_used_cells().size() != 2:
		failures.append("06_PhantomWall does not cover its two cells")
	if not wall.has_method("reveal"):
		failures.append("06_PhantomWall has no PhantomWallComponent2D")
	var solid := room.get_node_or_null("RoomContent/Terrain/SolidTiles") as TileMapLayer
	if solid == null:
		failures.append("components gallery has no SolidTiles layer")
		return
	for cell: Vector2i in [PHANTOM_CELL, PHANTOM_CELL + Vector2i.DOWN]:
		if solid.get_cell_source_id(cell) != -1:
			failures.append("the solid wall still covers the phantom cell %s" % cell)


func _assert_signs(entities: Node, failures: Array[String]) -> void:
	var signs := entities.get_node_or_null("Signs")
	if signs == null:
		failures.append("components gallery has no Signs node")
		return
	if signs.get_child_count() < 8:
		failures.append("components gallery signs do not label every station")


func _assert_world_registration(failures: Array[String]) -> void:
	var world := load(WORLD_PATH) as WorldData
	if world == null:
		failures.append("could not load the test world")
		return
	if not world.has_room(ROOM_ID):
		failures.append("components gallery is not registered in the test world")
		return
	if world.get_room_origin_chunk(ROOM_ID) != ROOM_ORIGIN:
		failures.append(
			"components gallery sits at chunk %s, expected %s"
			% [world.get_room_origin_chunk(ROOM_ID), ROOM_ORIGIN]
		)
	var room_data := world.get_room(ROOM_ID)
	if room_data == null or not FileAccess.file_exists(String(room_data.scene_path)):
		failures.append("components gallery baked runtime scene is missing")
