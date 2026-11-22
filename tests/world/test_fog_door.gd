extends Node

## The fog door is composed from components now: a solid body, DoorComponent2D
## and FogOccluderComponent2D. Opening it must clear both the collision and the
## sight blocker; closing it must restore both.

const DOOR_SCENE: PackedScene = preload("res://scenes/world/fog_door.tscn")
const RETIRED_SCRIPT := "res://scripts/world/fog_door.gd"
const DOOR_SIZE := Vector2(8.0, 16.0)


func run() -> Array[String]:
	var failures: Array[String] = []
	if FileAccess.file_exists(RETIRED_SCRIPT):
		failures.append("the bespoke FogDoor script still exists")
	var door := DOOR_SCENE.instantiate() as Node2D
	door.position = Vector2(32.0, 48.0)
	add_child(door)
	var body := door.get_node("Body") as StaticBody2D
	var shape := door.get_node("Body/CollisionShape2D") as CollisionShape2D
	var component := door.get_node("Door")
	var occluder := door.get_node("FogOccluder")
	if not bool(component.call("is_closed")):
		failures.append("door does not start closed")
	if not bool(occluder.call("is_occluding")):
		failures.append("closed door does not occlude sight")
	if occluder.call("get_world_rect") != Rect2(Vector2(32.0, 48.0), DOOR_SIZE):
		failures.append("door occluder rect does not match its cell size")
	if shape.disabled:
		failures.append("closed door collision is disabled")
	if body.collision_layer != 1:
		failures.append("closed door body is not solid")
	component.call("set_closed", false)
	if bool(component.call("is_closed")):
		failures.append("door did not open")
	if bool(occluder.call("is_occluding")):
		failures.append("open door still occludes sight")
	if not shape.disabled:
		failures.append("open door collision is still enabled")
	if body.collision_layer != 0:
		failures.append("open door body stayed solid")
	component.call("set_closed", true)
	if shape.disabled:
		failures.append("door did not restore its collision after closing")
	if not bool(occluder.call("is_occluding")):
		failures.append("closed door did not restore its sight blocker")
	component.set("blocks_sight", false)
	component.call("set_closed", false)
	component.call("set_closed", true)
	if bool(occluder.call("is_occluding")):
		failures.append("a see-through door occluded sight")
	component.set("blocks_sight", true)
	component.call("set_closed", false)
	component.call("set_closed", true)
	if not bool(occluder.call("is_occluding")):
		failures.append("restoring blocks_sight did not restore occlusion")
	component.set("size_cells", Vector2i(2, 3))
	if occluder.call("get_world_rect") != Rect2(Vector2(32.0, 48.0), Vector2(16.0, 24.0)):
		failures.append("resizing the door did not resize its sight blocker")
	if (body.get_parent() as Node) != door:
		failures.append("door body left the door node")
	door.free()
	return failures
