extends Node

const WORLD_ROOT := preload("res://scenes/runtime/world_root.tscn")
const SAVE_SNAPSHOT := preload("res://addons/platformer_kit/save/save_snapshot.gd")


class FakeSettings extends Node:
	var enabled := true

	func is_realtime_save_enabled() -> bool:
		return enabled


class FakeManager extends Node:
	var current_snapshot: RefCounted

	func set_resume_state(position: Vector2, velocity: Vector2, _immediate := false) -> bool:
		return current_snapshot != null and current_snapshot.set_resume_state(position, velocity)

	func clear_resume_state(_immediate := false) -> bool:
		if current_snapshot == null:
			return false
		current_snapshot.clear_resume_state()
		return true


func run() -> Array[String]:
	var failures: Array[String] = []
	var root := WORLD_ROOT.instantiate() as Node2D
	add_child(root)
	var service := root.get_node_or_null("RealtimeSave")
	if service == null:
		failures.append("world_root is missing the realtime save service")
		root.free()
		return failures
	var snapshot: RefCounted = SAVE_SNAPSHOT.new()
	snapshot.slot = 1
	var manager := FakeManager.new()
	manager.current_snapshot = snapshot
	add_child(manager)
	var settings := FakeSettings.new()
	add_child(settings)
	var player := root.get_node("Player") as Node2D
	service.call("bind_sources", player, manager, settings, root)
	if not bool(root.call("start_selected_snapshot", snapshot)):
		failures.append("world root could not start the realtime resume fixture")
		_cleanup(root, manager, settings)
		return failures

	var world: Resource = root.get("world_data")
	var runtime := root.get_node("WorldRuntime")
	var room_id := String(runtime.call("get_current_room_id"))
	var room_rect: Rect2i = world.call("get_room_pixel_rect", room_id)
	var target := Vector2(room_rect.position) + Vector2(room_rect.size) * 0.5
	var target_velocity := Vector2(12, -4)
	player.global_position = target
	player.set("velocity", target_velocity)
	if not bool(service.call("flush")):
		failures.append("realtime save flush did not record the live transform")
		_cleanup(root, manager, settings)
		return failures
	if not snapshot.has_resume:
		failures.append("realtime save flush left the snapshot without resume data")
		_cleanup(root, manager, settings)
		return failures

	root.call("stop")
	if not bool(root.call("start_selected_snapshot", snapshot)):
		failures.append("world root could not restart from the realtime snapshot")
	elif player.global_position != target:
		failures.append("world root did not resume the exact player position")
	elif Vector2(player.get("velocity")) != target_velocity:
		failures.append("world root did not resume the saved velocity")

	_cleanup(root, manager, settings)
	return failures


func _cleanup(root: Node, manager: Node, settings: Node) -> void:
	root.call("stop")
	root.free()
	manager.free()
	settings.free()
