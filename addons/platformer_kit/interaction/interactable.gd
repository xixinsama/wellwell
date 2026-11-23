class_name Interactable
extends Area2D

signal interacted(actor: Node)

@export var interaction_id: StringName
@export var interaction_priority := 0
@export var enabled := true


func can_interact(_actor: Node) -> bool:
	return enabled


func interact(actor: Node) -> bool:
	if not can_interact(actor):
		return false
	interacted.emit(actor)
	return true
