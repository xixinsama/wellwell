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
const PLAYER_STAMINA := preload("res://scripts/player/player_stamina.gd")
const MOTION_RULES := preload("res://scripts/player/player_motion_rules.gd")

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
var _state: int = PlayerMotionState.State.NORMAL
var _stamina: Node
var _game_freeze: Node

var _dash_direction := Vector2.ZERO
var _dash_remaining := 0.0
var _dash_speed := 240.0
var _dash_end_speed := 160.0
var _dash_preserved_x := 0.0
var _dash_refill_delay := 0.0
var _dash_just_started := false
var _dash_jump_buffered := false
var _ultra_applied := false
var _ducking := false
var _current_move_axis := 0.0

var _wall_direction := 0
var _wall_body: Node
var _wall_lockout_direction := 0
var _wall_slide_remaining := 0.0
var _climb_jump_refund_pending := false
var _was_in_water := false

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
	platform_on_leave = CharacterBody2D.PLATFORM_ON_LEAVE_DO_NOTHING
	_game_freeze = get_node_or_null("/root/GameFreeze")
	_stamina = get_node_or_null("Stamina")
	if _stamina == null:
		_stamina = PLAYER_STAMINA.new()
		_stamina.name = "Stamina"
		add_child(_stamina)
	_stamina.call("configure", tuning)
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


func get_input_source() -> RefCounted:
	return _input_source


func get_movement_context() -> RefCounted:
	return _movement_context


func get_character_sensors() -> RefCounted:
	return _sensors


func get_environment_snapshot() -> RefCounted:
	return _environment


func get_motion_state() -> int:
	return _state


func get_stamina() -> Node:
	return _stamina


func is_dash_attacking() -> bool:
	return _movement_context.dash_attack_remaining > 0.0


func is_ducking() -> bool:
	return _ducking


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
		_reset_motion_state()
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
	if _game_freeze != null and bool(_game_freeze.call("is_frozen")):
		return
	var profile := tuning as MOVEMENT_PROFILE
	if profile == null:
		return
	var intent := _input_source.call("get_intent") as CHARACTER_INTENT
	if intent == null:
		intent = CHARACTER_INTENT.new()
	_consume_frozen_input(intent)
	if intent.jump_pressed:
		_play_jump_intent_feedback()
	_capture_environment()
	_movement_context.velocity = velocity
	_current_move_axis = float(intent.move_axis)
	_update_ducking(intent)
	_update_timers(delta)
	var handled := false
	var water_handled := false
	if _state != PlayerMotionState.State.DASH and _wants_dash(intent):
		_start_dash(intent)
	if _state == PlayerMotionState.State.DASH:
		handled = _step_dash(intent, delta)
	elif _water_motion != null and bool(_water_motion.call("step", _movement_context, intent, _environment, profile, delta)):
		water_handled = true
		_leave_wall(false)
		_state = PlayerMotionState.State.NORMAL
		handled = true
	elif _ladder_motion != null and bool(_ladder_motion.call("step", _movement_context, intent, _environment, profile, delta)):
		_leave_wall(false)
		_state = PlayerMotionState.State.NORMAL
		handled = true
	elif _state == PlayerMotionState.State.WALL_GRAB or _state == PlayerMotionState.State.WALL_SLIDE:
		handled = _step_wall(intent, delta)
	elif _try_enter_wall(intent):
		handled = _step_wall(intent, delta)
	if not handled:
		_state = PlayerMotionState.State.NORMAL
		_step_normal(intent, delta)
	if _movement_context.just_jumped and not water_handled and _motion_effects != null:
		_motion_effects.call("play_jump")
	velocity = _movement_context.velocity
	_update_facing(intent.move_axis)
	_update_dash_recharge(delta)
	_update_one_way_piercing()
	_recover_visual(delta)
	_apply_corner_correction(delta)

	move_and_slide()
	var landed := _has_motion_sample and not was_on_floor and is_on_floor()
	if landed and _motion_effects != null:
		_motion_effects.call("play_land")
	_movement_context.velocity = velocity
	_world_velocity = get_real_velocity()
	if _motion_effects != null:
		_motion_effects.call("update_motion", delta, is_on_floor(), _world_velocity.x, facing)
	_has_motion_sample = true
	_post_move(delta)
	_capture_environment()
	was_on_floor = is_on_floor()
	if _hero_animation != null:
		_hero_animation.call("update_visual", delta, {
			"grounded": is_on_floor(), "velocity": velocity,
			"move_axis": intent.move_axis, "vertical_axis": intent.vertical_axis,
			"facing": facing, "just_jumped": _movement_context.just_jumped,
			"state": _state, "dash": _state == PlayerMotionState.State.DASH,
			"wall": _state == PlayerMotionState.State.WALL_GRAB,
			"wall_slide": _state == PlayerMotionState.State.WALL_SLIDE,
			"ducking": _ducking, "stamina": _stamina.call("get_current") if _stamina != null else 0.0,
		})


func _wants_dash(intent: RefCounted) -> bool:
	return intent.has_method("is_action_pressed") and bool(intent.call("is_action_pressed", &"dash"))


func _start_dash(intent: RefCounted) -> bool:
	if _ability_loadout == null or not _ability_loadout.has_method("try_start_dash"):
		return false
	var prior_velocity: Vector2 = _movement_context.velocity
	if not bool(_ability_loadout.call("try_start_dash", intent, _environment, facing)):
		return false
	var runtime := _ability_loadout.call("get_dash_runtime") as RefCounted
	var definition := _ability_loadout.call("get_dash_definition") as Resource
	if runtime == null or definition == null:
		return false
	_dash_direction = Vector2(runtime.call("get_dash_direction"))
	_dash_speed = maxf(0.0, float(definition.get("dash_speed")))
	_dash_end_speed = maxf(0.0, float(definition.get("end_speed")))
	_dash_preserved_x = 0.0
	if (
		_celeste_momentum_enabled()
		and absf(prior_velocity.x) > _dash_speed
		and not is_zero_approx(_dash_direction.x)
		and signf(prior_velocity.x) == signf(_dash_direction.x)
	):
		_dash_preserved_x = prior_velocity.x
	_dash_remaining = maxf(0.01, float(definition.get("dash_duration")))
	_movement_context.dash_attack_remaining = maxf(0.0, float(definition.get("dash_attack_seconds")))
	_dash_refill_delay = maxf(0.0, float(definition.get("refill_cooldown_seconds")))
	_dash_just_started = true
	_dash_jump_buffered = false
	_ultra_applied = false
	_ducking = false
	_movement_context.ducking = false
	_movement_context.force_move_x_remaining = 0.0
	_movement_context.climb_jump_window = 0.0
	_climb_jump_refund_pending = false
	_movement_context.velocity = Vector2.ZERO
	_state = PlayerMotionState.State.DASH
	if _game_freeze != null:
		_game_freeze.call("freeze", float(definition.get("freeze_seconds")))
	return true


func _step_dash(intent: RefCounted, delta: float) -> bool:
	if _dash_just_started:
		_dash_just_started = false
		_movement_context.velocity = Vector2.ZERO
		return true
	if intent.jump_pressed:
		_dash_jump_buffered = true
		if _try_dash_jump(intent):
			_dash_jump_buffered = false
			return true
	_dash_remaining = maxf(_dash_remaining - delta, 0.0)
	var dash_velocity := _dash_direction * _dash_speed
	if not is_zero_approx(_dash_preserved_x):
		dash_velocity.x = _dash_preserved_x
	_movement_context.velocity = dash_velocity + _capped_lift()
	if _dash_remaining <= 0.0:
		_movement_context.velocity = _dash_direction * _dash_end_speed
		_finish_dash()
	return true


func _try_dash_jump(intent: RefCounted) -> bool:
	if _movement_context.dash_attack_remaining <= 0.0:
		return false
	if _dash_direction.y < -0.5:
		var wall_side := _find_wall(_profile().wallbounce_check_distance)
		if wall_side != 0:
			_apply_wallbounce(-wall_side)
			return true
	if (
		(is_on_floor() or _environment.grounded or _movement_context.coyote_remaining > 0.0)
		and _dash_direction.y >= -0.5
	):
		var direction := MOTION_RULES.intent_direction(intent, facing)
		var duck := _ducking or _dash_direction.y > 0.5
		_apply_jump_velocity(MOTION_RULES.super_jump_velocity(_profile(), direction, duck))
		_finish_dash()
		return true
	return false


func _finish_dash() -> void:
	if _ability_loadout != null:
		var runtime := _ability_loadout.call("get_dash_runtime") as RefCounted
		if runtime != null and bool(runtime.get("active")):
			runtime.call("finish")
	_state = PlayerMotionState.State.NORMAL
	_dash_remaining = 0.0
	_dash_just_started = false
	_dash_preserved_x = 0.0
	_ultra_applied = false


func _apply_wallbounce(away_direction: int) -> void:
	_wall_lockout_direction = -away_direction
	_apply_jump_velocity(MOTION_RULES.wallbounce_velocity(_profile(), away_direction), 0.25)
	_movement_context.force_move_x = float(_profile().wallbounce_speed) * float(away_direction)
	_movement_context.force_move_x_remaining = _profile().wall_jump_force_time
	_movement_context.wall_grab_lockout = _profile().wall_grab_lockout
	_finish_dash()


func _step_normal(intent: RefCounted, delta: float) -> void:
	_motor.call("step", _movement_context, intent, _environment, _profile(), delta)
	if _movement_context.force_move_x_remaining > 0.0:
		_movement_context.velocity.x = _movement_context.force_move_x
		_movement_context.force_move_x_remaining = maxf(_movement_context.force_move_x_remaining - delta, 0.0)
	if intent.jump_pressed and _try_advanced_jump(intent):
		intent.jump_pressed = false
	_update_climb_jump_conversion(intent, delta)


func _try_advanced_jump(intent: RefCounted) -> bool:
	if _movement_context.dash_attack_remaining <= 0.0:
		return false
	if _dash_direction.y < -0.5:
		var wall_side := _find_wall(_profile().wallbounce_check_distance)
		if wall_side != 0:
			_apply_wallbounce(-wall_side)
			return true
		return false
	if _dash_direction.y > 0.5 and not is_on_floor():
		return false
	if not (is_on_floor() or _environment.grounded or _movement_context.coyote_remaining > 0.0):
		return false
	var direction := MOTION_RULES.intent_direction(intent, facing)
	var duck := _ducking or _dash_direction.y > 0.5
	_apply_jump_velocity(MOTION_RULES.super_jump_velocity(_profile(), direction, duck))
	return true


func _try_enter_wall(intent: RefCounted) -> bool:
	if is_on_floor():
		return false
	var direction := _wall_input_direction(intent)
	if direction == 0:
		return false
	if _movement_context.wall_grab_lockout > 0.0 and direction == _wall_lockout_direction:
		return false
	var probe := _wall_probe(direction, _profile().wall_check_distance)
	if probe.is_empty():
		return false
	_wall_direction = direction
	_wall_body = probe.get("body") as Node
	_snap_to_wall(direction, _profile().wall_check_distance + 1.0)
	_wall_slide_remaining = _profile().wall_slide_time
	if _stamina == null or bool(_stamina.call("is_tired")) or bool(_stamina.call("is_empty")):
		_state = PlayerMotionState.State.WALL_SLIDE
	else:
		_state = PlayerMotionState.State.WALL_GRAB
	_movement_context.velocity = Vector2.ZERO
	return true


func _step_wall(intent: RefCounted, delta: float) -> bool:
	if is_on_floor() or _wall_input_direction(intent) != _wall_direction:
		_leave_wall(true)
		return false
	var probe := _wall_probe(_wall_direction, _profile().wall_check_distance)
	if probe.is_empty():
		_leave_wall(true)
		return false
	_wall_body = probe.get("body") as Node
	if intent.jump_pressed and _try_wall_jump(intent):
		return true
	var carry := _wall_carry_velocity()
	if _state == PlayerMotionState.State.WALL_SLIDE:
		_wall_slide_remaining = maxf(_wall_slide_remaining - delta, 0.0)
		_movement_context.velocity.x = carry.x
		_movement_context.velocity.y = minf(
			_movement_context.velocity.y + _profile().gravity * delta,
			MOTION_RULES.wall_slide_cap(_profile(), _wall_slide_remaining)
		) + carry.y
		return true
	var vertical := float(intent.vertical_axis)
	if vertical < -0.5:
		_movement_context.velocity = carry + Vector2(0.0, -_profile().wall_climb_speed)
		if _stamina != null:
			_stamina.call("drain", _profile().stamina_climb_drain, delta)
	elif vertical > 0.5:
		_movement_context.velocity = carry + Vector2(0.0, _profile().climb_down_speed)
	else:
		_movement_context.velocity = carry
		if _stamina != null:
			_stamina.call("drain", _profile().stamina_grab_drain, delta)
	if _stamina != null and bool(_stamina.call("is_empty")):
		_state = PlayerMotionState.State.WALL_SLIDE
		_wall_slide_remaining = _profile().wall_slide_time
	return true


func _try_wall_jump(intent: RefCounted) -> bool:
	if _movement_context.dash_attack_remaining > 0.0 and _dash_direction.y < -0.5:
		var bounce_side := _find_wall(_profile().wallbounce_check_distance)
		if bounce_side != 0:
			_apply_wallbounce(-bounce_side)
			return true
	# Jump away by default, so holding toward a wall and tapping jump chains
	# left/right wall jumps without spending stamina. Climbing up is the
	# deliberate exception: hold up and jump.
	if float(intent.vertical_axis) < -0.5 and _stamina != null and not bool(_stamina.call("is_empty")):
		_apply_climb_jump()
	else:
		_apply_wall_jump()
	return true


func _apply_wall_jump() -> void:
	var away := -_wall_direction
	_wall_lockout_direction = _wall_direction
	_apply_jump_velocity(MOTION_RULES.wall_jump_velocity(_profile(), away))
	_movement_context.force_move_x = float(_profile().wall_jump_speed) * float(away)
	_movement_context.force_move_x_remaining = _profile().wall_jump_force_time
	_movement_context.wall_grab_lockout = _profile().wall_grab_lockout
	_leave_wall(false)


func _apply_climb_jump() -> void:
	if _stamina == null or not bool(_stamina.call("spend", _profile().climb_jump_stamina)):
		_apply_wall_jump()
		return
	_apply_jump_velocity(Vector2(0.0, _profile().jump_speed))
	_movement_context.climb_jump_window = _profile().climb_jump_convert_time
	_climb_jump_refund_pending = true
	_state = PlayerMotionState.State.NORMAL


func _update_climb_jump_conversion(intent: RefCounted, delta: float) -> void:
	if _movement_context.climb_jump_window <= 0.0:
		return
	var axis := float(intent.move_axis)
	if axis * float(_wall_direction) < -0.3:
		var away := -_wall_direction
		_movement_context.velocity.x = float(_profile().wall_jump_speed) * float(away)
		_movement_context.force_move_x = _movement_context.velocity.x
		_movement_context.force_move_x_remaining = _profile().wall_jump_force_time
		_movement_context.wall_grab_lockout = _profile().wall_grab_lockout
		_wall_lockout_direction = _wall_direction
		if _climb_jump_refund_pending and _stamina != null:
			_stamina.call("refund", _profile().climb_jump_stamina)
			_climb_jump_refund_pending = false
		_movement_context.climb_jump_window = 0.0
		return
	_movement_context.climb_jump_window = maxf(_movement_context.climb_jump_window - delta, 0.0)


func _leave_wall(reset_conversion: bool) -> void:
	_state = PlayerMotionState.State.NORMAL
	_wall_body = null
	if reset_conversion:
		_movement_context.climb_jump_window = 0.0
		_climb_jump_refund_pending = false


func _apply_jump_velocity(value: Vector2, var_time: float = -1.0) -> void:
	_movement_context.velocity = value
	_movement_context.var_jump_remaining = _profile().var_jump_time if var_time < 0.0 else var_time
	_movement_context.var_jump_speed = value.y
	_movement_context.jump_buffer_remaining = 0.0
	_movement_context.coyote_remaining = 0.0
	_movement_context.just_jumped = true
	_ducking = false
	_movement_context.ducking = false


func _wall_input_direction(intent: RefCounted) -> int:
	var axis := float(intent.move_axis)
	if axis > 0.3:
		return 1
	if axis < -0.3:
		return -1
	return 0


func _probe_wall(direction: int, distance: float) -> bool:
	return not _wall_probe(direction, distance).is_empty()


func _wall_probe(direction: int, distance: float) -> Dictionary:
	if direction == 0 or not is_inside_tree():
		return {}
	var collision := KinematicCollision2D.new()
	if not test_move(global_transform, Vector2(float(direction) * distance, 0.0), collision):
		return {}
	var normal := collision.get_normal()
	if normal.x * float(direction) >= -0.7:
		return {}
	return {
		"body": collision.get_collider() as Node,
		"normal": normal,
	}


func _snap_to_wall(direction: int, distance: float) -> void:
	if direction == 0 or distance <= 0.0:
		return
	move_and_collide(Vector2(float(direction) * distance, 0.0))


func _wall_carry_velocity() -> Vector2:
	if _wall_body == null or not is_instance_valid(_wall_body):
		return Vector2.ZERO
	if _wall_body.has_method("get_motion_velocity"):
		return Vector2(_wall_body.call("get_motion_velocity"))
	return Vector2.ZERO


func _find_wall(distance: float) -> int:
	var first := _wall_direction
	if first == 0:
		first = 1
	for direction: int in [first, -first]:
		if _probe_wall(direction, distance):
			return direction
	return 0


func _update_timers(delta: float) -> void:
	_movement_context.dash_attack_remaining = maxf(_movement_context.dash_attack_remaining - delta, 0.0)
	_movement_context.wall_grab_lockout = maxf(_movement_context.wall_grab_lockout - delta, 0.0)
	if _movement_context.wall_grab_lockout <= 0.0:
		_wall_lockout_direction = 0
	if _movement_context.climb_jump_window > 0.0:
		# The conversion function owns the countdown while normal movement is
		# active; this fallback keeps the window finite if another state owns
		# the frame.
		if _state != PlayerMotionState.State.NORMAL:
			_movement_context.climb_jump_window = maxf(_movement_context.climb_jump_window - delta, 0.0)
	_dash_refill_delay = maxf(_dash_refill_delay - delta, 0.0)


func _update_ducking(intent: RefCounted) -> void:
	if is_on_floor():
		if float(intent.vertical_axis) > 0.5:
			_ducking = true
	else:
		_ducking = false
	_movement_context.ducking = _ducking


func _post_move(_delta: float) -> void:
	if (
		is_on_floor()
		and _dash_jump_buffered
		and _dash_direction.y > 0.5
		and _movement_context.dash_attack_remaining > 0.0
	):
		_dash_jump_buffered = false
		var direction := 1 if _current_move_axis > 0.0 else (-1 if _current_move_axis < 0.0 else facing)
		if direction == 0:
			direction = 1
		_ducking = true
		_apply_jump_velocity(MOTION_RULES.super_jump_velocity(_profile(), direction, true))
		velocity = _movement_context.velocity
		if _state == PlayerMotionState.State.DASH:
			_finish_dash()
	if _state == PlayerMotionState.State.DASH and is_on_floor() and _dash_direction.y > 0.5:
		_ducking = true
		_movement_context.ducking = true
		if (
			_celeste_momentum_enabled()
			and not _ultra_applied
			and not _movement_context.velocity.is_zero_approx()
		):
			_ultra_applied = true
			_movement_context.velocity.x *= 1.2
			_movement_context.velocity.y = 0.0
			velocity = _movement_context.velocity
			_finish_dash()
	if is_on_floor() and _stamina != null:
		_stamina.call("refill")
	var in_water := _water_motion != null and bool(_water_motion.call("is_in_water"))
	if in_water and not _was_in_water and _stamina != null:
		_stamina.call("refill")
	_was_in_water = in_water


func _consume_frozen_input(intent: RefCounted) -> void:
	if _game_freeze == null:
		return
	if bool(_game_freeze.call("consume_buffered", &"jump")):
		intent.jump_pressed = true
	if bool(_game_freeze.call("consume_buffered", &"dash")):
		intent.press_action(&"dash")


func _update_dash_recharge(_delta: float) -> void:
	if _ability_loadout == null or not _ability_loadout.has_method("update_dash_recharge"):
		return
	if _dash_refill_delay > 0.0:
		return
	var in_water := _water_motion != null and bool(_water_motion.call("is_in_water"))
	_ability_loadout.call("update_dash_recharge", is_on_floor() or in_water)


## Compatibility seam for older composition tests: activation through the
## ability loadout still exposes the dash velocity without owning the state.
func _apply_ability_motion(intent: RefCounted) -> bool:
	if _ability_loadout == null or intent == null:
		return false
	var runtime := _ability_loadout.call("get_dash_runtime") as RefCounted
	if runtime == null or not bool(runtime.get("active")):
		if not bool(_ability_loadout.call("try_start_dash", intent, _environment, facing)):
			return false
		runtime = _ability_loadout.call("get_dash_runtime") as RefCounted
	if runtime == null or not bool(runtime.get("active")):
		return false
	velocity = Vector2(runtime.call("get_velocity_override"))
	_movement_context.velocity = velocity
	return true


## Dashes that travel in the direction a one-way surface blocks pass through it
## (down through a floor platform, sideways through a vertical one). The
## game-specific piercer component owns that rule.
func _apply_corner_correction(delta: float) -> void:
	if velocity.is_zero_approx():
		return
	var motion := velocity * delta
	var collision := KinematicCollision2D.new()
	if not test_move(global_transform, motion, collision):
		return
	var normal := collision.get_normal()
	if velocity.y < 0.0 and normal.y > 0.7:
		_try_upward_corner(motion)
	elif _state == PlayerMotionState.State.DASH and absf(_dash_direction.y) < 0.5:
		if absf(normal.x) > 0.7:
			_try_dash_corner(motion)


func _try_upward_corner(motion: Vector2) -> void:
	var limit := maxi(1, int(_profile().corner_correction))
	var first := -1 if velocity.x <= 0.0 else 1
	for side: int in [first, -first]:
		for offset_px: int in range(1, limit + 1):
			var offset := Vector2(float(side * offset_px), -1.0)
			if not test_move(global_transform.translated(offset), motion):
				global_position += offset
				return


func _try_dash_corner(motion: Vector2) -> void:
	var limit := maxi(1, int(_profile().corner_correction))
	for offset_px: int in range(1, limit + 1):
		for direction: int in [-1, 1]:
			var offset := Vector2(0.0, float(direction * offset_px))
			if not test_move(global_transform.translated(offset), motion):
				global_position += offset
				return


func _update_one_way_piercing() -> void:
	if _one_way_piercer == null:
		return
	_one_way_piercer.call("update", _state == PlayerMotionState.State.DASH, velocity)


func _capped_lift() -> Vector2:
	var value := Vector2(_environment.get("lift_velocity"))
	return Vector2(
		clampf(value.x, -_profile().lift_x_cap, _profile().lift_x_cap),
		clampf(value.y, _profile().lift_y_cap, 0.0)
	)


func _profile() -> MOVEMENT_PROFILE:
	return tuning as MOVEMENT_PROFILE


func _celeste_momentum_enabled() -> bool:
	var settings := get_node_or_null("/root/GlobalSettings")
	if settings == null or not settings.has_method("is_celeste_momentum_enabled"):
		return false
	return bool(settings.call("is_celeste_momentum_enabled"))


func _reset_motion_state() -> void:
	_state = PlayerMotionState.State.NORMAL
	_dash_direction = Vector2.ZERO
	_dash_remaining = 0.0
	_dash_refill_delay = 0.0
	_dash_just_started = false
	_dash_jump_buffered = false
	_dash_preserved_x = 0.0
	_ultra_applied = false
	_ducking = false
	_wall_direction = 0
	_wall_body = null
	_wall_lockout_direction = 0
	_wall_slide_remaining = 0.0
	_climb_jump_refund_pending = false
	_was_in_water = false
	if _ability_loadout != null:
		var runtime := _ability_loadout.call("get_dash_runtime") as RefCounted
		if runtime != null and bool(runtime.get("active")):
			runtime.call("cancel")
	if _stamina != null:
		_stamina.call("refill")
	if _game_freeze != null:
		_game_freeze.call("release")


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
	_reset_motion_state()
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
		"state": _state,
		"stamina": _stamina.call("get_current") if _stamina != null else 0.0,
		"dash_attack_remaining": _movement_context.dash_attack_remaining,
		"ducking": _ducking,
		"wall_direction": _wall_direction,
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
