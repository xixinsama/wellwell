class_name PlayerInteractionController
extends Node

## Turns a fresh `interact` press into one world interaction.
##
## The player owns a kit `InteractionDetector` that tracks nearby `Interactable`
## areas; this node only decides *when* the selected one is used. Menus pause the
## tree, which stops this node as well, so an open menu can never interact with
## the world. The action itself stays rebindable through the InputMapping addon:
## nothing here reads a key code.

const ACTION := &"interact"

@export var detector_path := NodePath("../InteractionDetector")

var _actor: Node2D
var _detector: Node


func _ready() -> void:
	_actor = get_parent() as Node2D
	_detector = get_node_or_null(detector_path)


func _physics_process(_delta: float) -> void:
	if not is_available():
		return
	if not Input.is_action_just_pressed(ACTION):
		return
	try_interact()


## Interacts with the current best candidate. Returns true when one consumed it.
func try_interact() -> bool:
	var target := get_candidate()
	if target == null or _actor == null or not is_instance_valid(_actor):
		return false
	return bool(target.call("interact", _actor))


## The `Interactable` the prompt should describe, or null.
func get_candidate() -> Node:
	if not is_available():
		return null
	if _detector == null or not is_instance_valid(_detector):
		return null
	if not _detector.has_method("get_best_candidate"):
		return null
	var candidate: Variant = _detector.call("get_best_candidate", _actor)
	if candidate is Node:
		return candidate as Node
	return null


## True while the actor may interact: in the tree, not paused, not control-locked.
func is_available() -> bool:
	if _actor == null or not is_instance_valid(_actor) or _actor.is_queued_for_deletion():
		return false
	if not is_inside_tree() or get_tree().paused:
		return false
	return not bool(_actor.get("control_locked"))


func has_candidate() -> bool:
	return get_candidate() != null
