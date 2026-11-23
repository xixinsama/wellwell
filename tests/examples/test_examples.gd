extends Node

## Merged test suite. Every inner class below is one original test file,
## kept in its own class so fixtures and helper names stay isolated. Do not
## add logic here: split a class back into its own file when it grows.

## tests/examples/test_ability_lab.gd
class AbilityLabCase extends Node:
	const LAB_SCENE := "res://examples/ability_lab/ability_lab.tscn"
	const DEFAULT_DASH := preload("res://addons/platformer_kit/abilities/dash/default_dash.tres")


	func run() -> Array[String]:
		var failures: Array[String] = []
		var packed := load(LAB_SCENE) as PackedScene
		if packed == null:
			return ["Ability Lab scene could not be loaded"]
		var lab := packed.instantiate()
		add_child(lab)
		var player := lab.get_node_or_null("Player")
		var pickup := lab.get_node_or_null("AbilityPickup")
		var ground := lab.get_node_or_null("Ground/CollisionShape2D")
		if player == null or pickup == null or ground == null:
			failures.append("Ability Lab is missing its interactive player, pickup, or ground")
		else:
			if pickup.get("ability_definition") != DEFAULT_DASH:
				failures.append("Ability Lab pickup does not use the reusable default Dash definition")
			if not pickup.call("collect_for", player):
				failures.append("Ability Lab pickup could not grant Dash to the reference player")
			var controller := player.get_node_or_null("AbilityLoadout/AbilityController")
			if controller == null or not controller.call("has_ability", &"dash"):
				failures.append("Ability Lab does not exercise reference player Dash integration")
		var status := lab.get_node_or_null("Status") as Label
		if status == null or status.text == "Ability runtime pending":
			failures.append("Ability Lab did not initialize observable runtime status")
		var source := FileAccess.get_file_as_string("res://examples/ability_lab/ability_lab.gd")
		if source.contains("ABILITY_DEFINITION.new") or source.contains("lab_dash"):
			failures.append("Ability Lab still builds a startup-only synthetic ability")
		lab.free()
		return failures


## tests/examples/test_movement_lab.gd
class MovementLabCase extends Node:
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
		var killzone := lab.find_child("Killzone", true, false)
		if killzone == null or not killzone.has_method("_on_body_entered"):
			failures.append("movement_lab is missing the reusable Killzone preview")
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


func run() -> Array[String]:
	var failures: Array[String] = []
	failures.append_array(_run_case(AbilityLabCase.new()))
	failures.append_array(_run_case(MovementLabCase.new()))
	return failures


func _run_case(test: Node) -> Array[String]:
	add_child(test)
	var result: Array = test.call("run")
	test.queue_free()
	var failures: Array[String] = []
	failures.assign(result)
	return failures
