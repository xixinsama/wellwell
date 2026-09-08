class_name Saveable
extends RefCounted


func get_persistent_id() -> StringName:
	return StringName()


func capture_save_state() -> Dictionary:
	return {}


func restore_save_state(_state: Dictionary) -> void:
	pass
