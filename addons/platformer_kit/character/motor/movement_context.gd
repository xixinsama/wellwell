class_name MovementContext
extends RefCounted

var velocity := Vector2.ZERO
var jump_buffer_remaining := 0.0
var coyote_remaining := 0.0
var just_jumped := false


func reset(initial_velocity: Vector2 = Vector2.ZERO) -> void:
	velocity = initial_velocity
	jump_buffer_remaining = 0.0
	coyote_remaining = 0.0
	just_jumped = false

