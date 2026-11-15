extends Node

const DOOR_SCENE: PackedScene = preload("res://scenes/world/fog_door.tscn")


func run() -> Array[String]:
	var failures: Array[String] = []
	var door := DOOR_SCENE.instantiate() as Node2D
	door.position = Vector2(32.0, 48.0)
	add_child(door)
	var body := door.get_node("Body") as StaticBody2D
	var shape := door.get_node("Body/CollisionShape2D") as CollisionShape2D
	if not bool(door.call("is_occluding")):
		failures.append("closed door does not occlude sight")
	if door.call("get_world_rect").size != Vector2(8, 16):
		failures.append("door world rect does not match its cell size")
	if shape.disabled:
		failures.append("closed door collision is disabled")
	door.call("set_closed", false)
	if bool(door.call("is_occluding")):
		failures.append("open door still occludes sight")
	if not shape.disabled:
		failures.append("open door collision is still enabled")
	door.call("set_closed", true)
	if body.get_parent() != door:
		failures.append("door body left the door node")
	if shape.disabled:
		failures.append("door did not restore its collision after closing")
	door.queue_free()
	return failures
