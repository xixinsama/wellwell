class_name CharacterSensors
extends RefCounted

const PROBE := preload("res://addons/platformer_kit/character/sensors/environment_probe.gd")
const SNAPSHOT := preload("res://addons/platformer_kit/character/environment/character_environment_snapshot.gd")

var _probe: RefCounted = PROBE.new()
var _snapshot: RefCounted = SNAPSHOT.new()


func set_probe(probe: RefCounted) -> bool:
	if probe == null or not probe.has_method("capture"):
		return false
	_probe = probe
	return true


func capture(body: CharacterBody2D) -> CharacterEnvironmentSnapshot:
	var result := _probe.call("capture", body) as CharacterEnvironmentSnapshot
	_snapshot = result if result != null else SNAPSHOT.new()
	return _snapshot as CharacterEnvironmentSnapshot


func get_snapshot() -> CharacterEnvironmentSnapshot:
	return _snapshot as CharacterEnvironmentSnapshot
