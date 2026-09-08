class_name CharacterIntent
extends RefCounted

var move_axis := 0.0
var jump_pressed := false
var jump_released := false
var jump_held := false
var fast_fall := false


func clear_transient() -> void:
	jump_pressed = false
	jump_released = false
