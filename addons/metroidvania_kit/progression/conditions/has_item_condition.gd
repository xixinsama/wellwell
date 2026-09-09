class_name HasItemCondition
extends "res://addons/metroidvania_kit/progression/conditions/condition.gd"

@export var item_id: StringName
@export_range(1, 999, 1) var minimum_count := 1


func evaluate(context: RefCounted) -> bool:
	return context != null and context.has_method("has_item") and context.call("has_item", item_id, minimum_count)
