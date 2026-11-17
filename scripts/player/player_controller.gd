extends CharacterBody2D
class_name PlayerController

signal climb_animation_requested(active: bool, direction: Vector2)

const PLAYER_TUNING_SCRIPT: Script = preload("res://scripts/player/player_tuning.gd")
const MOVEMENT_PROFILE := preload("res://addons/platformer_kit/character/resources/movement_profile.gd")
const CHARACTER_MOTOR := preload("res://addons/platformer_kit/character/motor/character_motor_2d.gd")
const MOVEMENT_CONTEXT := preload("res://addons/platformer_kit/character/motor/movement_context.gd")
const ENVIRONMENT_SNAPSHOT := preload("res://addons/platformer_kit/character/environment/character_environment_snapshot.gd")
const CHARACTER_SENSORS := preload("res://addons/platformer_kit/character/sensors/character_sensors.gd")
const CHARACTER_INTENT := preload("res://addons/platformer_kit/character/input/character_intent.gd")
const PLAYER_INPUT_SOURCE := preload("res://addons/platformer_kit/character/input/player_input_source.gd")

## Layer 4 ("void") blocks the player in jump mode only. Slider riding removes
## this bit so a rider can follow its piece through a void region.
const VOID_COLLISION_MASK := 1 << 3

@export var tuning: Resource
@export var spawn_position: Vector2 = Vector2.ZERO
@export var visual_recover_speed: float = 16.0

var facing: int = 1
var was_on_floor: bool = false
## When true (puzzle drag mode) the player ignores all input and freezes in
## place. PuzzleBoard toggles this and keeps the player riding a block.
var control_locked: bool = false

var _motor: RefCounted = CHARACTER_MOTOR.new()
var _movement_context: RefCounted = MOVEMENT_CONTEXT.new()
var _environment: RefCounted = ENVIRONMENT_SNAPSHOT.new()
var _sensors: RefCounted = CHARACTER_SENSORS.new()
var _input_source: RefCounted = PLAYER_INPUT_SOURCE.new()
var _world_velocity := Vector2.ZERO
var _has_motion_sample := false
var _ability_motion_active := false

@onready var sprite_root: Node2D = $SpriteRoot
@onready var _ability_loadout: Node = get_node_or_null("AbilityLoadout")
@onready var _motion_effects: Node = get_node_or_null("MotionEffects")
@onready var _ladder_motion: Node = get_node_or_null("LadderMotion")
@onready var _water_motion: Node = get_node_or_null("WaterMotion")
@onready var _hero_animation: Node = get_node_or_null("SpriteRoot/HeroAnimation")
@onready var _one_way_piercer: Node = get_node_or_null("OneWayDashPiercer")


func _ready() -> void:
    add_to_group("player")
    collision_mask |= VOID_COLLISION_MASK
    if tuning == null:
        tuning = PLAYER_TUNING_SCRIPT.new()
    if spawn_position == Vector2.ZERO:
        spawn_position = global_position
    _input_source.set("additional_actions", Array([&"dash"], TYPE_STRING_NAME, &"", null))
    if _one_way_piercer != null:
        _one_way_piercer.call("configure", self)
    if _ladder_motion != null and _ladder_motion.has_signal("climb_animation_requested"):
        _ladder_motion.connect("climb_animation_requested", _on_climb_animation_requested)
    if _water_motion != null and _water_motion.has_signal("swim_animation_requested"):
        _water_motion.connect("swim_animation_requested", _on_swim_animation_requested)


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


func grant_ability_definition(definition: Resource) -> bool:
    return _ability_loadout != null and bool(_ability_loadout.call("grant_ability_definition", definition))


func is_on_ladder() -> bool:
    return _ladder_motion != null and bool(_ladder_motion.call("is_on_ladder"))


func _on_climb_animation_requested(active: bool, direction: Vector2) -> void:
    climb_animation_requested.emit(active, direction)
    if _hero_animation != null:
        _hero_animation.call("set_climb_state", active, direction)


func _on_swim_animation_requested(active: bool, direction: Vector2) -> void:
    if _hero_animation != null:
        _hero_animation.call("set_swim_state", active, direction)


func set_control_locked(value: bool) -> void:
    control_locked = value
    set_void_collision_enabled(not value)
    if value:
        velocity = Vector2.ZERO
        _movement_context.velocity = Vector2.ZERO
        _world_velocity = Vector2.ZERO
        if _ladder_motion != null:
            _ladder_motion.call("reset")
        if _water_motion != null:
            _water_motion.call("reset")
        if _one_way_piercer != null:
            _one_way_piercer.call("clear")
        if _hero_animation != null:
            _hero_animation.call("reset")


## Grants exactly one jump that can be used without touching the floor. The
## puzzle board calls this after a rider has been carried by a slider and exits
## drag mode. A fresh jump press is required: stale coyote/buffer windows are
## cleared so the grant cannot be spent automatically on exit.
func grant_air_jump() -> void:
    _movement_context.air_jump_available = true
    _movement_context.coyote_remaining = 0.0
    _movement_context.jump_buffer_remaining = 0.0


func set_void_collision_enabled(enabled: bool) -> void:
    if enabled:
        collision_mask |= VOID_COLLISION_MASK
    else:
        collision_mask &= ~VOID_COLLISION_MASK


func _physics_process(delta: float) -> void:
    if control_locked:
        velocity = Vector2.ZERO
        _movement_context.velocity = Vector2.ZERO
        return
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
    var water_handled := false
    if _water_motion != null:
        water_handled = bool(_water_motion.call("step", _movement_context, intent, _environment, profile, delta))
    var ladder_handled := false
    if not water_handled and _ladder_motion != null:
        ladder_handled = bool(_ladder_motion.call("step", _movement_context, intent, _environment, profile, delta))
    if not water_handled and not ladder_handled:
        _motor.call("step", _movement_context, intent, _environment, profile, delta)
    if _movement_context.just_jumped and not water_handled and _motion_effects != null:
        _motion_effects.call("play_jump")
    velocity = _movement_context.velocity
    _update_facing(intent.move_axis)
    _update_dash_recharge()
    _apply_ability_motion(intent)
    _update_one_way_piercing()
    _recover_visual(delta)

    move_and_slide()
    var landed := _has_motion_sample and not was_on_floor and is_on_floor()
    if landed and _motion_effects != null:
        _motion_effects.call("play_land")
    _movement_context.velocity = velocity
    _world_velocity = get_real_velocity()
    if _motion_effects != null:
        _motion_effects.call("update_motion", delta, is_on_floor(), _world_velocity.x, facing)
    _has_motion_sample = true
    _capture_environment()
    was_on_floor = is_on_floor()
    if _hero_animation != null:
        _hero_animation.call("update_visual", delta, {
            "grounded": is_on_floor(), "velocity": velocity,
            "move_axis": intent.move_axis, "vertical_axis": intent.vertical_axis,
            "facing": facing, "just_jumped": _movement_context.just_jumped,
        })


func _apply_ability_motion(intent: RefCounted) -> bool:
    if _ability_loadout == null:
        _ability_motion_active = false
        return false
    var motion: Dictionary = _ability_loadout.call(
        "get_motion_override",
        intent,
        _environment,
        facing
    )
    if not bool(motion.get("active", false)):
        _ability_motion_active = false
        return false
    velocity = Vector2(motion.get("velocity", velocity))
    _movement_context.velocity = velocity
    _ability_motion_active = true
    return true


## The Dash recharges like a jump: touching the ground refills it, and swimming
## refills it every frame, so dashes are unlimited in water.
func _update_dash_recharge() -> void:
    if _ability_loadout == null or not _ability_loadout.has_method("update_dash_recharge"):
        return
    var in_water := _water_motion != null and bool(_water_motion.call("is_in_water"))
    _ability_loadout.call("update_dash_recharge", is_on_floor() or in_water)


## Dashes that travel in the direction a one-way surface blocks pass through it
## (down through a floor platform, sideways through a vertical one). The
## game-specific piercer component owns that rule.
func _update_one_way_piercing() -> void:
    if _one_way_piercer == null:
        return
    _one_way_piercer.call("update", _ability_motion_active, velocity)


func respawn_at(pos: Vector2) -> void:
    if _motion_effects != null:
        _motion_effects.call("clear_effects")
    if _one_way_piercer != null:
        _one_way_piercer.call("clear")
    if _hero_animation != null:
        _hero_animation.call("reset")
    _has_motion_sample = false
    global_position = pos
    if _ladder_motion != null:
        _ladder_motion.call("reset")
    if _water_motion != null:
        _water_motion.call("reset")
    spawn_position = pos
    velocity = Vector2.ZERO
    _world_velocity = Vector2.ZERO
    _movement_context.call("reset")
    sprite_root.scale = Vector2.ONE


func play_hurt_effect() -> void:
    if _motion_effects != null:
        _motion_effects.call("play_hurt")


func get_debug_state() -> Dictionary:
    return {
        "velocity": velocity,
        "relative_velocity": velocity,
        "platform_velocity": _environment.floor_velocity,
        "world_velocity": _world_velocity,
        "platform_id": _environment.platform_id,
        "on_floor": is_on_floor(),
        "jump_buffer_remaining": _movement_context.jump_buffer_remaining,
        "coyote_remaining": _movement_context.coyote_remaining,
        "air_jump_available": _movement_context.air_jump_available,
        "facing": facing,
        "ceiling": _environment.ceiling,
        "wall_left": _environment.wall_left,
        "wall_right": _environment.wall_right,
        "floor_normal": _environment.floor_normal,
    }


func _capture_environment() -> void:
    _environment = _sensors.call("capture", self)


func _update_facing(axis: float) -> void:
    if is_zero_approx(axis):
        return
    facing = -1 if axis < 0.0 else 1
    sprite_root.scale.x = absf(sprite_root.scale.x)


func _recover_visual(delta: float) -> void:
    var target_scale: Vector2 = Vector2.ONE
    var weight: float = 1.0 - exp(-visual_recover_speed * delta)
    sprite_root.scale = sprite_root.scale.lerp(target_scale, weight)


func _play_jump_intent_feedback() -> void:
    sprite_root.scale = Vector2(1.08, 0.92)
