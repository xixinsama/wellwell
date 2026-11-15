extends Node

## The gas layer follows the Game setting, live.

const ATMOSPHERE := preload("res://scripts/world/atmosphere/atmosphere.gd")


class FakeSettings extends RefCounted:
	signal settings_changed

	var enabled := true

	func is_atmosphere_enabled() -> bool:
		return enabled

	func set_atmosphere_enabled(value: bool) -> void:
		enabled = value
		settings_changed.emit()


func run() -> Array[String]:
	var failures: Array[String] = []
	var atmosphere := ATMOSPHERE.new() as Node2D
	add_child(atmosphere)
	if not bool(atmosphere.call("is_enabled")):
		failures.append("gas layer starts disabled")
	atmosphere.call("set_enabled", false)
	if bool(atmosphere.call("is_enabled")):
		failures.append("set_enabled(false) did not disable the gas layer")
	atmosphere.call("set_enabled", true)

	var settings := FakeSettings.new()
	atmosphere.call("bind_settings_source", settings)
	if not bool(atmosphere.call("is_enabled")):
		failures.append("gas layer ignored the enabled setting")
	settings.set_atmosphere_enabled(false)
	if bool(atmosphere.call("is_enabled")):
		failures.append("gas layer ignored a live settings change")
	settings.set_atmosphere_enabled(true)
	if not bool(atmosphere.call("is_enabled")):
		failures.append("gas layer did not turn back on")

	atmosphere.queue_free()
	return failures
