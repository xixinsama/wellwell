extends Node

const DETECTOR := preload("res://addons/platformer_kit/interaction/interaction_detector.gd")
const INTERACTABLE := preload("res://addons/platformer_kit/interaction/interactable.gd")
const CONTROLLER := preload("res://game/interaction/player_interaction_controller.gd")


class FakeActor extends CharacterBody2D:
	var control_locked := false


func run() -> Array[String]:
	var failures: Array[String] = []
	_assert_interact_uses_the_candidate(failures)
	_assert_locked_actor_ignores_presses(failures)
	_assert_paused_tree_ignores_presses(failures)
	return failures


func _make_rig() -> Dictionary:
	var actor := FakeActor.new()
	var detector := Area2D.new()
	detector.name = "InteractionDetector"
	detector.set_script(DETECTOR)
	detector.collision_layer = 0
	detector.collision_mask = 4
	actor.add_child(detector)
	var controller := Node.new()
	controller.name = "InteractionController"
	controller.set_script(CONTROLLER)
	actor.add_child(controller)
	add_child(actor)
	var target := INTERACTABLE.new() as Area2D
	target.name = "Target"
	target.position = Vector2(8.0, 0.0)
	add_child(target)
	return {"actor": actor, "detector": detector, "controller": controller, "target": target}


func _register(rig: Dictionary) -> Array[Node]:
	var hits: Array[Node] = []
	(rig["target"] as Node).connect(
		&"interacted", func(actor: Node) -> void: hits.append(actor)
	)
	(rig["detector"] as Node).call("register_candidate", rig["target"])
	return hits


func _assert_interact_uses_the_candidate(failures: Array[String]) -> void:
	var rig := _make_rig()
	var hits := _register(rig)
	var controller := rig["controller"] as Node
	if not bool(controller.call("try_interact")):
		failures.append("interaction controller refused a registered candidate")
	if hits.size() != 1 or hits[0] != rig["actor"]:
		failures.append("interaction controller did not pass its actor to the interactable")
	if controller.call("get_candidate") != rig["target"]:
		failures.append("interaction controller did not expose the selected candidate")
	(rig["target"] as Node).free()
	(rig["actor"] as Node).free()


func _assert_locked_actor_ignores_presses(failures: Array[String]) -> void:
	var rig := _make_rig()
	var hits := _register(rig)
	(rig["actor"] as Node).set("control_locked", true)
	var controller := rig["controller"] as Node
	if bool(controller.call("try_interact")):
		failures.append("a control-locked actor still interacted")
	if controller.call("get_candidate") != null or not hits.is_empty():
		failures.append("a control-locked actor still selected a candidate")
	(rig["target"] as Node).free()
	(rig["actor"] as Node).free()


func _assert_paused_tree_ignores_presses(failures: Array[String]) -> void:
	var rig := _make_rig()
	var hits := _register(rig)
	get_tree().paused = true
	var controller := rig["controller"] as Node
	if bool(controller.call("try_interact")) or not hits.is_empty():
		failures.append("interaction controller interacted while the tree was paused")
	get_tree().paused = false
	(rig["target"] as Node).free()
	(rig["actor"] as Node).free()
