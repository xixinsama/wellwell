class_name PlayerMotionEffects
extends Node2D

const PIXEL_FX := preload("res://addons/pixelfx/nodes/pixel_fx_2d.gd")
const JUMP_DUST := preload("res://game/player/effects/jump_dust.gd")
const RUN_DUST := preload("res://game/player/effects/run_dust.gd")
const LAND_DUST := preload("res://game/player/effects/land_dust.gd")
const RESPAWN_HURT := preload("res://game/player/effects/respawn_hurt.gd")

@export var run_min_speed := 8.0
@export var run_step_interval := 0.14

var _run_cooldown := 0.0


func play_jump() -> void:
	_spawn(JUMP_DUST)


func play_land() -> void:
	_run_cooldown = run_step_interval
	_spawn(LAND_DUST)


func play_hurt() -> void:
	_spawn(RESPAWN_HURT)


func update_motion(delta: float, grounded: bool, horizontal_speed: float, facing: int) -> void:
	if not grounded or absf(horizontal_speed) < run_min_speed:
		_run_cooldown = 0.0
		return
	_run_cooldown = maxf(_run_cooldown - maxf(delta, 0.0), 0.0)
	if _run_cooldown > 0.0:
		return
	_spawn(RUN_DUST, facing < 0, Vector2(-2.0 * float(facing), 0.0))
	_run_cooldown = run_step_interval


func clear_effects() -> void:
	_run_cooldown = 0.0
	for child: Node in get_children():
		if child is CanvasItem:
			child.hide()
		child.queue_free()


func _spawn(effect_script: Script, flipped: bool = false, offset: Vector2 = Vector2.ZERO) -> Node2D:
	var fx := PIXEL_FX.new() as Node2D
	fx.top_level = true
	fx.z_index = 1
	fx.set("effect_script", effect_script)
	fx.set("autoplay", false)
	fx.set("free_when_done", true)
	fx.set("flip", flipped)
	fx.set("additive_light", false)
	add_child(fx)
	fx.global_position = global_position + offset
	fx.call("play")
	return fx
