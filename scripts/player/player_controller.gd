extends CharacterBody2D
class_name PlayerController

const PLAYER_TUNING_SCRIPT: Script = preload("res://scripts/player/player_tuning.gd")

@export var tuning: Resource
@export var spawn_position: Vector2 = Vector2.ZERO
@export var visual_recover_speed: float = 16.0

var facing: int = 1
var jump_buffer_until: float = -1.0
var coyote_until: float = -1.0
var was_on_floor: bool = false

@onready var sprite_root: Node2D = $SpriteRoot


func _ready() -> void:
    if tuning == null:
        tuning = PLAYER_TUNING_SCRIPT.new()
    if spawn_position == Vector2.ZERO:
        spawn_position = global_position


func _input(event: InputEvent) -> void:
    if event.is_action_pressed("jump"):
        jump_buffer_until = _now() + tuning.jump_buffer_time
        _play_jump_intent_feedback()


func _physics_process(delta: float) -> void:
    var current_time: float = _now()
    var axis: float = Input.get_axis("move_left", "move_right")

    _update_facing(axis)
    _apply_horizontal(axis, delta)
    _update_coyote(current_time)
    _try_jump(current_time)
    _apply_gravity(delta)
    _recover_visual(delta)

    move_and_slide()
    was_on_floor = is_on_floor()


func respawn_at(pos: Vector2) -> void:
    global_position = pos
    spawn_position = pos
    velocity = Vector2.ZERO
    jump_buffer_until = -1.0
    coyote_until = -1.0
    sprite_root.scale = Vector2(facing, 1.0)


func get_debug_state() -> Dictionary:
    var current_time: float = _now()
    return {
        "velocity": velocity,
        "on_floor": is_on_floor(),
        "jump_buffer_remaining": maxf(jump_buffer_until - current_time, 0.0),
        "coyote_remaining": maxf(coyote_until - current_time, 0.0),
        "facing": facing,
    }


func _apply_horizontal(axis: float, delta: float) -> void:
    var target_speed: float = axis * tuning.max_speed
    var has_input: bool = not is_zero_approx(axis)
    var accel: float = tuning.ground_accel if is_on_floor() else tuning.air_accel
    var decel: float = tuning.ground_decel if is_on_floor() else tuning.air_decel
    var rate: float = accel if has_input else decel
    velocity.x = move_toward(velocity.x, target_speed, rate * delta)


func _apply_gravity(delta: float) -> void:
    if is_on_floor() and velocity.y >= 0.0:
        velocity.y = 0.0
        return

    var gravity_scale: float = 1.0
    if velocity.y < 0.0 and not Input.is_action_pressed("jump"):
        gravity_scale = tuning.jump_cut_gravity_multiplier
    elif velocity.y > 0.0:
        gravity_scale = tuning.fall_gravity_multiplier

    if velocity.y > 0.0 and Input.is_action_pressed("move_down"):
        gravity_scale *= tuning.fast_fall_multiplier

    velocity.y += tuning.gravity * gravity_scale * delta
    velocity.y = minf(velocity.y, tuning.max_fall_speed)


func _update_coyote(current_time: float) -> void:
    if is_on_floor():
        coyote_until = current_time + tuning.coyote_time


func _try_jump(current_time: float) -> void:
    if current_time > jump_buffer_until:
        return
    if current_time > coyote_until:
        return

    velocity.y = tuning.jump_speed
    jump_buffer_until = -1.0
    coyote_until = -1.0
    sprite_root.scale = Vector2(float(facing) * 0.82, 1.18)


func _update_facing(axis: float) -> void:
    if is_zero_approx(axis):
        return
    facing = -1 if axis < 0.0 else 1
    sprite_root.scale.x = absf(sprite_root.scale.x) * float(facing)


func _recover_visual(delta: float) -> void:
    var target_scale: Vector2 = Vector2(float(facing), 1.0)
    var weight: float = 1.0 - exp(-visual_recover_speed * delta)
    sprite_root.scale = sprite_root.scale.lerp(target_scale, weight)


func _play_jump_intent_feedback() -> void:
    sprite_root.scale = Vector2(float(facing) * 1.08, 0.92)


func _now() -> float:
    return Time.get_ticks_msec() / 1000.0
