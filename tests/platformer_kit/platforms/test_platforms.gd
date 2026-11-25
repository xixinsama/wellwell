extends Node

## Merged test suite. Every inner class below is one original test file,
## kept in its own class so fixtures and helper names stay isolated. Do not
## add logic here: split a class back into its own file when it grows.

## tests/platformer_kit/platforms/test_elevator_motion.gd
class ElevatorMotionCase extends Node:
	const ELEVATOR: Script = preload("res://addons/platformer_kit/platforms/components/elevator_motion_component_2d.gd")


	func run() -> Array[String]:
		var failures: Array[String] = []
		var lift: Node = ELEVATOR.new()
		lift.set("travel", Vector2(0, -100))
		lift.set("speed", 50)
		lift.set("top_wait_seconds", 0.2)
		lift.set("bottom_wait_seconds", 0.1)
		if lift.call("sample_velocity", 0.1) != Vector2.ZERO:
			failures.append("elevator moved before a rider arrived")
		if not bool(lift.call("activate")):
			failures.append("elevator refused the first rider")
		if bool(lift.call("activate")):
			failures.append("elevator restarted while already moving")
		var highest := 0.0
		for step in 40:
			lift.call("sample_velocity", 0.1)
			highest = minf(highest, Vector2(lift.call("get_offset")).y)
		if absf(highest + 100.0) > 1.0:
			failures.append("elevator did not reach its travel offset: %s" % highest)
		var lowest := 0.0
		for step in 60:
			lift.call("sample_velocity", 0.1)
			lowest = maxf(lowest, Vector2(lift.call("get_offset")).y)
		if absf(lowest) > 1.0:
			failures.append("elevator did not return to its base: %s" % lowest)
		if not bool(lift.call("activate")):
			failures.append("elevator refused a rider after returning")
		lift.free()
		return failures


## tests/platformer_kit/platforms/test_fog_occluder.gd
class FogOccluderCase extends Node:
	## Contract for FogOccluderComponent2D: it publishes the host body's collision
	## footprint to the fog, and it only asks the fog to rebuild when that footprint
	## crosses an 8 px cell.

	const OCCLUDER_SCRIPT: Script = preload(
		"res://addons/platformer_kit/platforms/components/fog_occluder_component_2d.gd"
	)
	const OCCLUDER_GROUP := &"fog_occluder"


	class FakeFog extends Node:
		var refreshes := 0

		func _ready() -> void:
			add_to_group(&"fog_of_war")

		func request_refresh() -> void:
			refreshes += 1


	func run() -> Array[String]:
		var failures: Array[String] = []
		_assert_footprint_follows_shapes(failures)
		_assert_state_changes_registration(failures)
		_assert_refresh_only_on_cell_change(failures)
		_assert_size_override(failures)
		return failures


	func _make_body(offset: Vector2, shape_size: Vector2, shape_offset: Vector2) -> StaticBody2D:
		var body := StaticBody2D.new()
		body.position = offset
		var shape_node := CollisionShape2D.new()
		var rectangle := RectangleShape2D.new()
		rectangle.size = shape_size
		shape_node.shape = rectangle
		shape_node.position = shape_offset
		body.add_child(shape_node)
		return body


	func _assert_footprint_follows_shapes(failures: Array[String]) -> void:
		var body := _make_body(Vector2(40.0, 24.0), Vector2(16.0, 8.0), Vector2(8.0, 4.0))
		add_child(body)
		var occluder: Node = OCCLUDER_SCRIPT.new()
		body.add_child(occluder)
		if not occluder.is_in_group(OCCLUDER_GROUP):
			failures.append("fog occluder did not join the fog_occluder group")
		if not bool(occluder.call("is_occluding")):
			failures.append("enabled fog occluder does not occlude")
		if occluder.call("get_world_rect") != Rect2(40.0, 24.0, 16.0, 8.0):
			failures.append("fog occluder rect does not follow the host collision shape")
		body.free()


	func _assert_state_changes_registration(failures: Array[String]) -> void:
		var body := _make_body(Vector2.ZERO, Vector2(8.0, 16.0), Vector2(4.0, 8.0))
		add_child(body)
		var occluder: Node = OCCLUDER_SCRIPT.new()
		body.add_child(occluder)
		occluder.call("set_blocking", false)
		if bool(occluder.call("is_occluding")):
			failures.append("a see-through fog occluder still occludes")
		if not occluder.is_in_group(OCCLUDER_GROUP):
			failures.append("clearing blocks_sight dropped the occluder from the group")
		occluder.call("set_blocking", true)
		if not bool(occluder.call("is_occluding")):
			failures.append("restoring blocks_sight did not re-enable occlusion")
		occluder.call("set_enabled", false)
		if bool(occluder.call("is_occluding")) or occluder.is_in_group(OCCLUDER_GROUP):
			failures.append("disabled fog occluder stayed registered")
		occluder.call("set_enabled", true)
		if not occluder.is_in_group(OCCLUDER_GROUP) or not bool(occluder.call("is_occluding")):
			failures.append("re-enabling the fog occluder did not register it again")
		body.free()


	func _assert_refresh_only_on_cell_change(failures: Array[String]) -> void:
		var fog := FakeFog.new()
		add_child(fog)
		var body := _make_body(Vector2.ZERO, Vector2(4.0, 4.0), Vector2(2.0, 2.0))
		add_child(body)
		var occluder: Node = OCCLUDER_SCRIPT.new()
		body.add_child(occluder)
		if bool(occluder.call("refresh_if_moved")):
			failures.append("fog occluder refreshed without moving")
		body.position += Vector2(4.0, 0.0)
		if bool(occluder.call("refresh_if_moved")):
			failures.append("fog occluder refreshed inside the same cell")
		if fog.refreshes != 0:
			failures.append("fog occluder asked the fog to rebuild inside the same cell")
		body.position += Vector2(1.0, 0.0)
		if not bool(occluder.call("refresh_if_moved")):
			failures.append("fog occluder did not refresh after crossing a cell")
		if fog.refreshes != 1:
			failures.append("fog occluder did not reach the fog_of_war group exactly once")
		occluder.call("refresh")
		if fog.refreshes != 2:
			failures.append("explicit refresh did not reach the fog_of_war group")
		fog.free()
		body.free()


	func _assert_size_override(failures: Array[String]) -> void:
		var body := _make_body(Vector2.ZERO, Vector2(8.0, 8.0), Vector2(4.0, 4.0))
		add_child(body)
		var occluder: Node = OCCLUDER_SCRIPT.new()
		occluder.set("size_override", Vector2(8.0, 16.0))
		occluder.set("position", Vector2(16.0, 24.0))
		body.add_child(occluder)
		if occluder.call("get_world_rect") != Rect2(16.0, 24.0, 8.0, 16.0):
			failures.append("size override did not replace the host footprint")
		occluder.set("footprint_offset", Vector2(2.0, 2.0))
		if occluder.call("get_world_rect") != Rect2(18.0, 26.0, 8.0, 16.0):
			failures.append("footprint offset was not applied to the size override")
		occluder.set("size_override", Vector2.ZERO)
		if occluder.call("get_world_rect") != Rect2(0.0, 0.0, 8.0, 8.0):
			failures.append("clearing the size override did not restore the host footprint")
		body.free()


## tests/platformer_kit/platforms/test_platform_motion.gd
class PlatformMotionCase extends Node:
	const BODY_PATH := "res://addons/platformer_kit/platforms/platform_body_2d.gd"
	const MOTION_PATH := "res://addons/platformer_kit/platforms/components/platform_motion_component_2d.gd"
	const WAYPOINT_PATH := "res://addons/platformer_kit/platforms/components/waypoint_motion_component_2d.gd"
	const FALL_PATH := "res://addons/platformer_kit/platforms/components/fall_motion_component_2d.gd"
	const RIDER_TRIGGER_PATH := "res://addons/platformer_kit/platforms/components/rider_trigger_component_2d.gd"
	const CONVEYOR_PATH := "res://addons/platformer_kit/platforms/components/conveyor_surface_component_2d.gd"
	const REMOVED_ONE_WAY_PATH := "res://addons/platformer_kit/platforms/one_way_platform.gd"
	const REMOVED_PING_PONG_PATH := "res://addons/platformer_kit/platforms/components/ping_pong_motion_component_2d.gd"


	func run() -> Array[String]:
		var failures: Array[String] = []
		var scripts := _load_contract_scripts(failures)
		if not failures.is_empty():
			return failures
		_assert_waypoint_routes(scripts, failures)
		_assert_composed_motion(scripts, failures)
		_assert_fall_collision_policies(scripts, failures)
		_assert_rider_activation(scripts, failures)
		_assert_conveyor_surface(scripts, failures)
		_assert_native_one_way(failures)
		return failures


	func _load_contract_scripts(failures: Array[String]) -> Dictionary:
		var scripts := {}
		for path: String in [BODY_PATH, MOTION_PATH, WAYPOINT_PATH, FALL_PATH, RIDER_TRIGGER_PATH, CONVEYOR_PATH]:
			var script := load(path) as Script
			if script == null or not script.can_instantiate():
				failures.append("platform component could not be loaded: %s" % path)
			else:
				scripts[path] = script
		return scripts


	func _assert_waypoint_routes(scripts: Dictionary, failures: Array[String]) -> void:
		var motion: Node = scripts[WAYPOINT_PATH].new()
		motion.waypoints = PackedVector2Array([Vector2.ZERO, Vector2(10.0, 0.0), Vector2(10.0, 10.0)])
		motion.travel_speed = 10.0
		motion.arrival_pause_seconds = 0.25
		var reached: Array[int] = []
		motion.waypoint_reached.connect(func(index: int) -> void: reached.append(index))
		var first_velocity: Vector2 = motion.sample_velocity(1.0)
		if first_velocity != Vector2(10.0, 0.0) or reached != [1]:
			failures.append("waypoint motion did not arrive exactly at point 2")
		if not motion.sample_velocity(0.25).is_zero_approx():
			failures.append("waypoint motion did not pause after arrival")
		motion.sample_velocity(1.0)
		motion.sample_velocity(0.25)
		motion.sample_velocity(1.0)
		motion.sample_velocity(0.25)
		motion.sample_velocity(1.0)
		if reached != [1, 2, 1, 0]:
			failures.append("ping-pong waypoint order was not 1,2,3,2,1")
		motion.loop_mode = motion.LoopMode.CYCLE
		motion.reset_component()
		reached.clear()
		motion.sample_velocity(1.0)
		motion.sample_velocity(0.25)
		motion.sample_velocity(1.0)
		motion.sample_velocity(0.25)
		motion.sample_velocity(2.0)
		motion.sample_velocity(0.25)
		if reached != [1, 2, 0]:
			failures.append("cycle waypoint order was not 1,2,3,1")
		if motion.get_current_waypoint_index() != 0:
			failures.append("cycle motion did not expose its current waypoint")
		motion.waypoints = PackedVector2Array([Vector2.ONE, Vector2(10.0, 0.0)])
		motion.reset_component()
		if motion.is_route_valid() or not motion.sample_velocity(1.0).is_zero_approx():
			failures.append("waypoint motion accepted a route that does not begin at zero")
		motion.free()
		if FileAccess.file_exists(REMOVED_PING_PONG_PATH):
			failures.append("obsolete PingPongMotionComponent2D still exists")


	func _assert_composed_motion(scripts: Dictionary, failures: Array[String]) -> void:
		var body: AnimatableBody2D = scripts[BODY_PATH].new()
		body.platform_id = &"lab:moving_fall"
		var waypoint: Node = scripts[WAYPOINT_PATH].new()
		waypoint.waypoints = PackedVector2Array([Vector2.ZERO, Vector2(120.0, 0.0)])
		waypoint.travel_speed = 120.0
		body.add_child(waypoint)
		var fall: Node = scripts[FALL_PATH].new()
		fall.gravity = 100.0
		fall.terminal_velocity = 200.0
		body.add_child(fall)
		add_child(body)
		fall.activate()
		body.advance_motion(0.25)
		var velocity: Vector2 = body.get_motion_velocity()
		if velocity.x <= 0.0 or velocity.y <= 0.0:
			failures.append("PlatformBody2D did not combine ping-pong and fall motion")
		if body.get_platform_id() != &"lab:moving_fall":
			failures.append("PlatformBody2D did not expose stable identity")
		body.free()


	func _assert_fall_collision_policies(scripts: Dictionary, failures: Array[String]) -> void:
		var fall: Node = scripts[FALL_PATH].new()
		fall.gravity = 100.0
		fall.activate()
		fall.sample_velocity(0.5)
		if not fall.blocks_on_collision():
			failures.append("fall motion should stop on collision by default")
		fall.on_motion_collision(Vector2.UP)
		if fall.is_active() or not fall.has_landed() or not fall.sample_velocity(0.5).is_zero_approx():
			failures.append("fall motion did not stop after landing on an upward normal")
		fall.reset_component()
		fall.start_active = true
		fall.reset_component()
		if not fall.is_active():
			failures.append("fall motion did not restore its configured start state")
		fall.start_active = false
		fall.reset_component()
		fall.collision_mode = fall.CollisionMode.IGNORE_COLLISIONS
		fall.activate()
		if fall.blocks_on_collision():
			failures.append("fall motion could not opt out of environment collision")
		fall.free()


	func _assert_rider_activation(scripts: Dictionary, failures: Array[String]) -> void:
		var root := Node2D.new()
		var fall: Node = scripts[FALL_PATH].new()
		fall.name = "FallMotion"
		root.add_child(fall)
		var trigger: Area2D = scripts[RIDER_TRIGGER_PATH].new()
		var target_paths: Array[NodePath] = [NodePath("../FallMotion")]
		trigger.target_paths = target_paths
		root.add_child(trigger)
		add_child(root)
		var rider := CharacterBody2D.new()
		trigger.trigger_body(rider)
		if not fall.is_active():
			failures.append("RiderTriggerComponent2D did not activate its target component")
		rider.free()
		root.free()


	func _assert_conveyor_surface(scripts: Dictionary, failures: Array[String]) -> void:
		var body := StaticBody2D.new()
		var conveyor: Node = scripts[CONVEYOR_PATH].new()
		conveyor.surface_velocity = Vector2(64.0, 0.0)
		body.add_child(conveyor)
		add_child(body)
		conveyor.apply_surface_velocity()
		if body.constant_linear_velocity != Vector2(64.0, 0.0):
			failures.append("ConveyorSurfaceComponent2D did not use Godot surface velocity")
		body.free()


	func _assert_native_one_way(failures: Array[String]) -> void:
		if FileAccess.file_exists(REMOVED_ONE_WAY_PATH):
			failures.append("redundant OneWayPlatform script still exists")
		var collision := CollisionShape2D.new()
		collision.one_way_collision = true
		if not collision.one_way_collision:
			failures.append("native CollisionShape2D one-way collision is unavailable")
		collision.free()


func run() -> Array[String]:
	var failures: Array[String] = []
	failures.append_array(_run_case(ElevatorMotionCase.new()))
	failures.append_array(_run_case(FogOccluderCase.new()))
	failures.append_array(_run_case(PlatformMotionCase.new()))
	return failures


func _run_case(test: Node) -> Array[String]:
	add_child(test)
	var result: Array = test.call("run")
	test.queue_free()
	var failures: Array[String] = []
	failures.assign(result)
	return failures
