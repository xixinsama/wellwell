extends Node

const MOVING_PATH := "res://addons/platformer_kit/platforms/moving_platform.gd"
const ONE_WAY_PATH := "res://addons/platformer_kit/platforms/one_way_platform.gd"
const FALLING_PATH := "res://addons/platformer_kit/platforms/falling_platform.gd"
const CONVEYOR_PATH := "res://addons/platformer_kit/platforms/conveyor_platform.gd"


func run() -> Array[String]:
	var failures: Array[String] = []
	for path: String in [MOVING_PATH, ONE_WAY_PATH, FALLING_PATH, CONVEYOR_PATH]:
		var script := load(path) as Script
		if script == null or not script.can_instantiate():
			failures.append("platform script could not be loaded: %s" % path)
	if not failures.is_empty():
		return failures

	var moving: Node = load(MOVING_PATH).new()
	moving.platform_id = &"lab:moving"
	moving.travel_offset = Vector2(120.0, 0.0)
	moving.cycle_duration = 2.0
	moving.reset_motion(Vector2.ZERO)
	moving.advance_motion(0.25)
	if moving.get_platform_id() != &"lab:moving":
		failures.append("MovingPlatform did not expose its stable identity")
	if moving.get_platform_velocity().x <= 0.0:
		failures.append("MovingPlatform did not expose current platform velocity")
	moving.free()

	var conveyor: Node = load(CONVEYOR_PATH).new()
	conveyor.platform_id = &"lab:conveyor"
	conveyor.conveyor_velocity = Vector2(64.0, 0.0)
	if conveyor.get_platform_velocity() != Vector2(64.0, 0.0):
		failures.append("ConveyorPlatform did not expose conveyor velocity")
	if conveyor.get_platform_id() != &"lab:conveyor":
		failures.append("ConveyorPlatform did not expose its stable identity")
	conveyor.free()

	var falling: Node = load(FALLING_PATH).new()
	falling.gravity = 100.0
	falling.activate()
	falling.advance_motion(0.5)
	if falling.get_platform_velocity().y <= 0.0:
		failures.append("FallingPlatform did not accelerate after activation")
	falling.free()
	return failures
