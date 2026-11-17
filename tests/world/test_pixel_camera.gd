extends Node

const CAMERA_PATH := "res://addons/platformer_kit/camera/pixel_camera_2d.gd"


func run() -> Array[String]:
	var failures: Array[String] = []
	var script := load(CAMERA_PATH) as Script
	if script == null or not script.can_instantiate():
		return ["PixelCamera2D could not be loaded"]
	var camera := script.new() as Camera2D
	if not camera.has_method("set_room_bounds"):
		failures.append("PixelCamera2D is missing set_room_bounds")
	if not camera.has_method("clear_room_bounds"):
		failures.append("PixelCamera2D is missing clear_room_bounds")
	if not camera.has_method("set_camera_mode"):
		failures.append("PixelCamera2D is missing set_camera_mode")
	if failures.is_empty():
		camera.set("camera_mode", 0)
		camera.call("set_room_bounds", Rect2(Vector2.ZERO, Vector2(640, 180)))
		if camera.get("camera_mode") != 0:
			failures.append("supplying room bounds changed free camera mode")
		camera.call("set_camera_mode", 1)
		camera.global_position = Vector2(1000, 1000)
		camera.set("smoothed_position", Vector2(1000, 1000))
		camera.call("set_room_bounds", Rect2(Vector2.ZERO, Vector2(320, 180)))
		if not bool(camera.get("room_lock_is_fixed")):
			failures.append("one-chunk room was not marked fixed")
		if camera.global_position != Vector2(160, 90) or camera.get("smoothed_position") != Vector2(160, 90):
			failures.append("room change did not immediately clamp old camera state")
		camera.call("set_room_bounds", Rect2(Vector2.ZERO, Vector2(640, 180)))
		var left_target: Vector2 = camera.call("get_room_camera_target", Vector2.ZERO, Vector2(320, 180))
		var right_target: Vector2 = camera.call("get_room_camera_target", Vector2(640, 90), Vector2(320, 180))
		if left_target != Vector2(160, 90) or right_target != Vector2(480, 90):
			failures.append("multi-chunk room camera did not move within room bounds")
		camera.call("clear_room_bounds")
		if camera.get("camera_mode") != 1:
			failures.append("clear_room_bounds changed the authored camera mode")
		_assert_room_transition_modes(camera, failures)
	camera.free()
	return failures


## A room switch is either a hard cut or a glide, and the setting has to be able to
## pick: cutting also has to drop the engine's own position smoothing, otherwise the
## camera keeps easing towards the new room while every overlay already rebound there.
func _assert_room_transition_modes(camera: Camera2D, failures: Array[String]) -> void:
	if not camera.has_method("set_smooth_room_transition"):
		failures.append("PixelCamera2D is missing set_smooth_room_transition")
		return
	if not camera.has_method("snap_to_room"):
		failures.append("PixelCamera2D is missing snap_to_room")
		return
	camera.set("camera_mode", 1)
	camera.call("set_room_bounds", Rect2(Vector2(320, 0), Vector2(320, 180)))
	if camera.position_smoothing_enabled:
		failures.append("camera smoothed by default; the instant cut is the default")
	camera.call("set_smooth_room_transition", true)
	if not camera.position_smoothing_enabled:
		failures.append("smooth transition did not turn camera smoothing on")
	camera.call("set_room_bounds", Rect2(Vector2.ZERO, Vector2(320, 180)))
	camera.global_position = Vector2(1000, 1000)
	camera.call("set_smooth_room_transition", false)
	if camera.position_smoothing_enabled:
		failures.append("instant transition kept camera smoothing on")
	var target := Node2D.new()
	add_child(target)
	target.global_position = Vector2(900, 90)
	camera.call("bind_target", target)
	camera.call("snap_to_room")
	if camera.global_position != Vector2(160, 90):
		failures.append("snap_to_room did not land on the room centre (%s)" % str(camera.global_position))
	if camera.get("smoothed_position") != Vector2(160, 90):
		failures.append("snap_to_room left a stale smoothed position behind")
	remove_child(target)
	target.free()

