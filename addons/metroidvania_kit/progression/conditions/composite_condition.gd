class_name CompositeCondition
extends "res://addons/metroidvania_kit/progression/conditions/condition.gd"

enum Operator {
	ALL,
	ANY,
	NONE,
}

@export var operator := Operator.ALL
@export var conditions: Array[Resource] = []


func evaluate(context: RefCounted) -> bool:
	match operator:
		Operator.ALL:
			for condition: Resource in conditions:
				if not _evaluate_child(condition, context):
					return false
			return true
		Operator.ANY:
			for condition: Resource in conditions:
				if _evaluate_child(condition, context):
					return true
			return false
		Operator.NONE:
			for condition: Resource in conditions:
				if _evaluate_child(condition, context):
					return false
			return true
	return false


func _evaluate_child(condition: Resource, context: RefCounted) -> bool:
	return condition != null and condition.has_method("evaluate") and condition.call("evaluate", context)
