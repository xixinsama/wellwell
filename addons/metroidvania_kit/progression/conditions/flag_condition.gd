class_name FlagCondition
extends "res://addons/metroidvania_kit/progression/conditions/condition.gd"

@export var flag_id: StringName
@export var expected_value := true


func evaluate(context: RefCounted) -> bool:
	return (
		context != null
		and context.has_method("get_flag")
		and bool(context.call("get_flag", flag_id, false)) == expected_value
	)
