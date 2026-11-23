extends Node

const SENSORS_PATH := "res://addons/platformer_kit/character/sensors/character_sensors.gd"
const PROBE_PATH := "res://addons/platformer_kit/character/sensors/environment_probe.gd"
const SNAPSHOT_PATH := "res://addons/platformer_kit/character/environment/character_environment_snapshot.gd"

class FakeProbe extends RefCounted:
	var snapshot: RefCounted

	func capture(_body: CharacterBody2D) -> RefCounted:
		return snapshot


func run() -> Array[String]:
	var failures: Array[String] = []
	var sensors_script := load(SENSORS_PATH) as Script
	var probe_script := load(PROBE_PATH) as Script
	var snapshot_script := load(SNAPSHOT_PATH) as Script
	if sensors_script == null or probe_script == null or snapshot_script == null:
		return ["character sensor scripts could not be loaded"]

	var body := CharacterBody2D.new()
	var probe := FakeProbe.new()
	var expected: RefCounted = snapshot_script.new()
	expected.grounded = true
	expected.ceiling = true
	expected.wall_left = true
	expected.wall_right = false
	expected.floor_normal = Vector2(0.25, -0.9682458)
	expected.floor_velocity = Vector2(48.0, 0.0)
	expected.on_moving_platform = true
	probe.snapshot = expected

	var sensors: RefCounted = sensors_script.new()
	sensors.set_probe(probe)
	var actual = sensors.capture(body)
	if actual == null:
		failures.append("CharacterSensors did not produce a snapshot")
	else:
		if not actual.grounded or not actual.ceiling or not actual.wall_left or actual.wall_right:
			failures.append("CharacterSensors lost floor, ceiling, or wall contact state")
		if not actual.floor_normal.is_equal_approx(expected.floor_normal):
			failures.append("CharacterSensors lost the captured floor normal")
		if actual.floor_velocity != expected.floor_velocity or not actual.on_moving_platform:
			failures.append("CharacterSensors lost moving-platform velocity")
	if sensors.get_snapshot() != actual:
		failures.append("CharacterSensors did not retain the current frame snapshot")
	body.free()
	return failures
