extends Node

const SERVICE_PATH := "res://scripts/save/realtime_save_service.gd"
const SAVE_SNAPSHOT := preload("res://addons/platformer_kit/save/save_snapshot.gd")


class FakePlayer extends CharacterBody2D:
	pass


class FakeSettings extends Node:
	signal settings_changed

	var enabled := true

	func is_realtime_save_enabled() -> bool:
		return enabled

	func set_enabled(value: bool) -> void:
		enabled = value
		settings_changed.emit()


class FakeManager extends Node:
	var current_snapshot: RefCounted = SAVE_SNAPSHOT.new()
	var set_calls := 0
	var clear_calls := 0
	var last_position := Vector2.ZERO
	var last_velocity := Vector2.ZERO
	var last_immediate := false

	func set_resume_state(position: Vector2, velocity: Vector2, immediate := false) -> bool:
		set_calls += 1
		last_position = position
		last_velocity = velocity
		last_immediate = immediate
		return current_snapshot.set_resume_state(position, velocity)

	func clear_resume_state(immediate := false) -> bool:
		clear_calls += 1
		last_immediate = immediate
		current_snapshot.clear_resume_state()
		return true


func run() -> Array[String]:
	var failures: Array[String] = []
	var script := load(SERVICE_PATH) as Script
	if script == null or not script.can_instantiate():
		return ["realtime save service is missing: %s" % SERVICE_PATH]
	var service: Node = script.new() as Node
	if service == null:
		return ["realtime save service could not be instantiated"]
	add_child(service)
	var player := FakePlayer.new()
	player.name = "FakePlayer"
	add_child(player)
	var manager := FakeManager.new()
	manager.name = "FakeManager"
	add_child(manager)
	var settings := FakeSettings.new()
	settings.name = "FakeSettings"
	add_child(settings)
	if not service.has_method("bind_sources"):
		failures.append("realtime save service is missing bind_sources")
		_cleanup(service, player, manager, settings)
		return failures
	service.call("bind_sources", player, manager, settings)

	player.global_position = Vector2(64, 32)
	player.velocity = Vector2(10, -2)
	service.call("set_active", true)
	if manager.set_calls != 1:
		failures.append("world activation did not capture the live transform")
	if manager.last_position != Vector2(64, 32) or manager.last_velocity != Vector2(10, -2):
		failures.append("realtime save captured the wrong transform")

	if bool(service.call("capture_now")):
		failures.append("realtime save rewrote an unchanged transform")
	if manager.set_calls != 1:
		failures.append("unchanged transform still reached the save manager")

	player.global_position = Vector2(80, 40)
	if not bool(service.call("capture_now")):
		failures.append("realtime save ignored a moved player")
	if manager.last_position != Vector2(80, 40):
		failures.append("realtime save did not update the moved position")

	settings.set_enabled(false)
	if manager.clear_calls != 1:
		failures.append("disabling realtime save did not clear resume data")
	if bool(manager.current_snapshot.get("has_resume")):
		failures.append("disabling realtime save left resume data behind")
	if bool(service.call("capture_now")):
		failures.append("realtime save kept capturing after being disabled")

	settings.set_enabled(true)
	if manager.set_calls != 3:
		failures.append("realtime save did not resume after being re-enabled")
	var before_flush := manager.set_calls
	if not bool(service.call("flush")):
		failures.append("realtime save flush failed")
	if manager.set_calls != before_flush + 1 or not manager.last_immediate:
		failures.append("flush did not force an immediate save")

	service.call("set_active", false)
	if bool(service.call("capture_now")):
		failures.append("realtime save captured while the session was inactive")

	_cleanup(service, player, manager, settings)
	return failures


func _cleanup(service: Node, player: Node, manager: Node, settings: Node) -> void:
	service.free()
	player.free()
	manager.free()
	settings.free()
