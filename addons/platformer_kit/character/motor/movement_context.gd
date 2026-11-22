class_name MovementContext
extends RefCounted

var velocity := Vector2.ZERO
var jump_buffer_remaining := 0.0
var coyote_remaining := 0.0
var just_jumped := false
## One extra jump granted by an external carry (for example a puzzle rider).
## It is consumed by the next jump and cleared when the character lands.
var air_jump_available := false

## Current falling cap. It approaches the normal cap or the fast-fall cap.
var max_fall_current := 160.0
## Remaining held-button window that clamps rising speed.
var var_jump_remaining := 0.0
var var_jump_speed := 0.0
## Post-climb-jump window that may convert the jump into a wall jump.
var climb_jump_window := 0.0
## Time left in the dash-attack window after a dash starts.
var dash_attack_remaining := 0.0
## Time left before holding toward a wall may grab it again.
var wall_grab_lockout := 0.0
## Horizontal velocity forced after a wall jump, and its remaining time.
var force_move_x := 0.0
var force_move_x_remaining := 0.0
var ducking := false


func reset(initial_velocity: Vector2 = Vector2.ZERO) -> void:
	velocity = initial_velocity
	jump_buffer_remaining = 0.0
	coyote_remaining = 0.0
	just_jumped = false
	air_jump_available = false
	max_fall_current = 160.0
	var_jump_remaining = 0.0
	var_jump_speed = 0.0
	climb_jump_window = 0.0
	dash_attack_remaining = 0.0
	wall_grab_lockout = 0.0
	force_move_x = 0.0
	force_move_x_remaining = 0.0
	ducking = false
