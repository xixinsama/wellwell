class_name DamageEvent
extends RefCounted

var data: Resource
var source: Node
var target: Node
var direction := Vector2.ZERO


static func create(damage_data: Resource, source_node: Node, target_node: Node) -> RefCounted:
	var event: RefCounted = load("res://addons/platformer_combat/runtime/damage_event.gd").new()
	event.data = damage_data
	event.source = source_node
	event.target = target_node
	if damage_data != null:
		event.direction = Vector2(damage_data.get("impulse")).normalized()
	return event
