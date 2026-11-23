class_name HeroAnimationController
extends Node2D

@export var run_threshold := 85.0
@export var idle_delay := 2.0

@onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D

var _climb_active := false
var _climb_direction := Vector2.ZERO
var _swim_active := false
var _swim_direction := Vector2.ZERO
var _idle_elapsed := 0.0
var _current := ""
var _facing := 1


func set_climb_state(active: bool, direction: Vector2) -> void:
	_climb_active = active
	_climb_direction = direction
	_idle_elapsed = 0.0


func set_swim_state(active: bool, direction: Vector2) -> void:
	_swim_active = active
	_swim_direction = direction
	_idle_elapsed = 0.0


func reset() -> void:
	_climb_active = false
	_climb_direction = Vector2.ZERO
	_swim_active = false
	_swim_direction = Vector2.ZERO
	_idle_elapsed = 0.0
	_current = ""
	_facing = 1
	_sprite.stop()
	_sprite.flip_h = false


func get_current_animation() -> String:
	return _current


func update_visual(delta: float, state: Dictionary) -> void:
	var grounded := bool(state.get("grounded", false))
	var velocity := Vector2(state.get("velocity", Vector2.ZERO))
	var move_axis := float(state.get("move_axis", 0.0))
	var vertical_axis := float(state.get("vertical_axis", 0.0))
	var just_jumped := bool(state.get("just_jumped", false))
	var wall_active := bool(state.get("wall", false))
	var wall_sliding := bool(state.get("wall_slide", false))
	var dash_active := bool(state.get("dash", false))
	var ducking := bool(state.get("ducking", false))
	_facing = int(state.get("facing", _facing))
	var horizontal_speed := absf(velocity.x)
	var has_input := absf(move_axis) > 0.01 or absf(vertical_axis) > 0.01
	var has_motion := horizontal_speed >= 1.0 or (_climb_active and not _climb_direction.is_zero_approx())
	if has_input or has_motion or just_jumped or _swim_active or (not grounded and not _climb_active):
		_idle_elapsed = 0.0
	else:
		_idle_elapsed += maxf(delta, 0.0)
	var target := ""
	if dash_active:
		target = "jump"
	elif _swim_active:
		target = "swim" if _sprite.sprite_frames.has_animation(&"swim") else "climb"
	elif wall_active and absf(vertical_axis) > 0.01:
		target = "climb"
	elif wall_sliding:
		target = "fall"
	elif wall_active:
		target = "climb"
	elif _climb_active and absf(_climb_direction.y) > 0.01:
		target = "climb"
	elif not grounded and not _climb_active:
		target = "jump" if velocity.y < 0.0 else "fall"
	elif grounded and ducking:
		target = "look_down"
	elif grounded and absf(vertical_axis) > 0.01:
		target = "look_up" if vertical_axis < 0.0 else "look_down"
	elif horizontal_speed >= 1.0:
		target = "run" if horizontal_speed >= run_threshold else "walk"
	elif _idle_elapsed >= idle_delay:
		target = "idle"
	else:
		target = "look_left" if _facing < 0 else "look_right"
	_play(target, just_jumped and target == "jump")


func _play(target: String, restart: bool) -> void:
	if target != _current or restart:
		_current = target
		if restart:
			_sprite.stop()
		_sprite.play(StringName(target))
	_sprite.flip_h = _facing < 0 and not target.begins_with("look_")
