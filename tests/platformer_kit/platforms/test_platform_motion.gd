extends Node

const BODY_PATH := "res://addons/platformer_kit/platforms/platform_body_2d.gd"
const MOTION_PATH := "res://addons/platformer_kit/platforms/components/platform_motion_component_2d.gd"
const PING_PONG_PATH := "res://addons/platformer_kit/platforms/components/ping_pong_motion_component_2d.gd"
const FALL_PATH := "res://addons/platformer_kit/platforms/components/fall_motion_component_2d.gd"
const RIDER_TRIGGER_PATH := "res://addons/platformer_kit/platforms/components/rider_trigger_component_2d.gd"
const CONVEYOR_PATH := "res://addons/platformer_kit/platforms/components/conveyor_surface_component_2d.gd"
const REMOVED_ONE_WAY_PATH := "res://addons/platformer_kit/platforms/one_way_platform.gd"


func run() -> Array[String]:
	var failures: Array[String] = []
	var scripts := _load_contract_scripts(failures)
	if not failures.is_empty():
		return failures
	_assert_composed_motion(scripts, failures)
	_assert_fall_collision_policies(scripts, failures)
	_assert_rider_activation(scripts, failures)
	_assert_conveyor_surface(scripts, failures)
	_assert_native_one_way(failures)
	return failures


func _load_contract_scripts(failures: Array[String]) -> Dictionary:
	var scripts := {}
	for path: String in [BODY_PATH, MOTION_PATH, PING_PONG_PATH, FALL_PATH, RIDER_TRIGGER_PATH, CONVEYOR_PATH]:
		var script := load(path) as Script
		if script == null or not script.can_instantiate():
			failures.append("platform component could not be loaded: %s" % path)
		else:
			scripts[path] = script
	return scripts


func _assert_composed_motion(scripts: Dictionary, failures: Array[String]) -> void:
	var body: AnimatableBody2D = scripts[BODY_PATH].new()
	body.platform_id = &"lab:moving_fall"
	var ping: Node = scripts[PING_PONG_PATH].new()
	ping.travel_offset = Vector2(120.0, 0.0)
	ping.cycle_duration = 2.0
	body.add_child(ping)
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
