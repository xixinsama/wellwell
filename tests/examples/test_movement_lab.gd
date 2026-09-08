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
	lab.free()
	return failures
