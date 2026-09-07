extends Node

const CAMERA_PATH := "res://scripts/camera/pixel_camera_2d.gd"


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
		camera.call("clear_room_bounds")
		if camera.get("camera_mode") != 1:
			failures.append("clear_room_bounds changed the authored camera mode")
	camera.free()
	return failures
