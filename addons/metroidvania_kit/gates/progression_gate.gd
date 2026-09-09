class_name ProgressionGate
extends Node2D

signal access_granted(context: RefCounted)
signal access_denied(context: RefCounted)

@export var condition: Resource


func allows(context: RefCounted) -> bool:
	return condition == null or (condition.has_method("evaluate") and condition.call("evaluate", context))


func request_access(context: RefCounted) -> bool:
	var result := allows(context)
	if result:
		access_granted.emit(context)
	else:
		access_denied.emit(context)
	return result
