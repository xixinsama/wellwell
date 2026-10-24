extends Node2D

## Minimal player stand-in for board tests that only need the rider jump
## grant seam. The real PlayerController owns the movement-context behavior.

var control_locked: bool = false
var air_jump_grants: int = 0


func set_control_locked(value: bool) -> void:
	control_locked = value


func grant_air_jump() -> void:
	air_jump_grants += 1
