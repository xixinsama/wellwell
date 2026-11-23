class_name HasAbilityCondition
extends "res://addons/metroidvania_kit/progression/conditions/condition.gd"

@export var ability_id: StringName


func evaluate(context: RefCounted) -> bool:
	return context != null and context.has_method("has_ability") and context.call("has_ability", ability_id)
