extends Node

const LAB_PATH := "res://examples/movement_lab/movement_lab.tscn"
const REQUIRED_FIXTURES := [
	"Slope",
	"OneWayPlatform",
	"MovingPlatform",
	"LowCeiling",
	"Wall",
	"NarrowGap",
	"FallingPlatform",
	"ConveyorPlatform",
	"CombinedMovingFallingPlatform",
]


func run() -> Array[String]:
	var failures: Array[String] = []
	var packed := load(LAB_PATH) as PackedScene
	if packed == null:
		return ["movement_lab scene could not be loaded"]
	var lab := packed.instantiate()
	for fixture_name: String in REQUIRED_FIXTURES:
		if lab.find_child(fixture_name, true, false) == null:
			failures.append("movement_lab is missing fixture: %s" % fixture_name)
	var player := lab.find_child("Player", true, false)
	if player == null or not player.has_method("get_movement_context"):
		failures.append("movement_lab is missing the framework-composed player")
	var camera := lab.find_child("PixelCamera2D", true, false)
	if camera == null or not camera.has_method("set_room_bounds"):
		failures.append("movement_lab is missing the framework camera")
	var one_way := lab.find_child("OneWayPlatform", true, false)
	var one_way_shape := one_way.find_child("CollisionShape2D", true, false) as CollisionShape2D if one_way != null else null
	if one_way_shape == null or not one_way_shape.one_way_collision:
		failures.append("movement_lab one-way fixture does not use native collision")
	for fixture_name: String in ["MovingPlatform", "FallingPlatform", "CombinedMovingFallingPlatform"]:
		var fixture := lab.find_child(fixture_name, true, false)
		if fixture == null or not fixture.has_method("get_motion_velocity"):
			failures.append("movement_lab fixture is not component-hosted: %s" % fixture_name)
	var waypoint := lab.find_child("WaypointMotion", true, false)
	if waypoint == null or not waypoint.has_method("get_current_waypoint_index"):
		failures.append("movement_lab moving fixture has no waypoint motion component")
	var conveyor := lab.find_child("ConveyorPlatform", true, false)
	if conveyor == null or not conveyor.has_method("get_platform_id") or conveyor.find_child("ConveyorSurface", false, false) == null:
		failures.append("movement_lab conveyor has no surface component")
	lab.free()
	return failures
