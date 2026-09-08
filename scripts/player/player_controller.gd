extends CharacterBody2D
class_name PlayerController

const PLAYER_TUNING_SCRIPT: Script = preload("res://scripts/player/player_tuning.gd")
const MOVEMENT_PROFILE := preload("res://addons/platformer_kit/character/resources/movement_profile.gd")
const CHARACTER_MOTOR := preload("res://addons/platformer_kit/character/motor/character_motor_2d.gd")
const MOVEMENT_CONTEXT := preload("res://addons/platformer_kit/character/motor/movement_context.gd")
const ENVIRONMENT_SNAPSHOT := preload("res://addons/platformer_kit/character/environment/character_environment_snapshot.gd")
const CHARACTER_SENSORS := preload("res://addons/platformer_kit/character/sensors/character_sensors.gd")
const CHARACTER_INTENT := preload("res://addons/platformer_kit/character/input/character_intent.gd")
const PLAYER_INPUT_SOURCE := preload("res://addons/platformer_kit/character/input/player_input_source.gd")

@export var tuning: Resource
@export var spawn_position: Vector2 = Vector2.ZERO
@export var visual_recover_speed: float = 16.0

var facing: int = 1
var was_on_floor: bool = false

var _motor: RefCounted = CHARACTER_MOTOR.new()
var _movement_context: RefCounted = MOVEMENT_CONTEXT.new()
var _environment: RefCounted = ENVIRONMENT_SNAPSHOT.new()
var _sensors: RefCounted = CHARACTER_SENSORS.new()
var _input_source: RefCounted = PLAYER_INPUT_SOURCE.new()

@onready var sprite_root: Node2D = $SpriteRoot


func _ready() -> void:
    if tuning == null:
        tuning = PLAYER_TUNING_SCRIPT.new()
    if spawn_position == Vector2.ZERO:
        spawn_position = global_position


func set_input_source(value: RefCounted) -> bool:
    if value == null or not value.has_method("get_intent"):
        return false
    _input_source = value
    return true


func get_movement_context() -> RefCounted:
    return _movement_context


func get_character_sensors() -> RefCounted:
    return _sensors


func get_environment_snapshot() -> RefCounted:
    return _environment


func _physics_process(delta: float) -> void:
    var profile := tuning as MOVEMENT_PROFILE
    if profile == null:
        return
    var intent := _input_source.call("get_intent") as CHARACTER_INTENT
    if intent == null:
        intent = CHARACTER_INTENT.new()
    if intent.jump_pressed:
        _play_jump_intent_feedback()
    _capture_environment()
    _movement_context.velocity = velocity
    _motor.call("step", _movement_context, intent, _environment, profile, delta)
    velocity = _movement_context.velocity
    _update_facing(intent.move_axis)
    _recover_visual(delta)

    move_and_slide()
    _movement_context.velocity = velocity
    was_on_floor = is_on_floor()


func respawn_at(pos: Vector2) -> void:
    global_position = pos
    spawn_position = pos
    velocity = Vector2.ZERO
    _movement_context.call("reset")
    sprite_root.scale = Vector2(facing, 1.0)


func get_debug_state() -> Dictionary:
    return {
        "velocity": velocity,
        "on_floor": is_on_floor(),
        "jump_buffer_remaining": _movement_context.jump_buffer_remaining,
        "coyote_remaining": _movement_context.coyote_remaining,
        "facing": facing,
        "ceiling": _environment.ceiling,
        "wall_left": _environment.wall_left,
        "wall_right": _environment.wall_right,
        "floor_normal": _environment.floor_normal,
        "platform_velocity": _environment.floor_velocity,
    }


func _capture_environment() -> void:
    _environment = _sensors.call("capture", self)


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
