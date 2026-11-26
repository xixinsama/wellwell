class_name AutopilotMotion
extends RefCounted

## Deterministic movement simulator for the autopilot planner.
##
## It mirrors the shipped character controller for the subset the planner can
## issue: normal run/fall/jump, the eight-direction dash and the jumps that
## follow it, ladders, and wall grab / wall climb / wall jump / climb jump. All
## collision is resolved against [AutopilotGrid], so a leg is pure arithmetic and
## the same leg can be replayed tick by tick by the driver.

const MOVEMENT_CONTEXT := preload("res://addons/platformer_kit/character/motor/movement_context.gd")
const CHARACTER_MOTOR := preload("res://addons/platformer_kit/character/motor/character_motor_2d.gd")
const ENVIRONMENT := preload(
	"res://addons/platformer_kit/character/environment/character_environment_snapshot.gd"
)
const CHARACTER_INTENT := preload("res://addons/platformer_kit/character/input/character_intent.gd")
const LEG := preload("res://addons/platformer_kit/character/autopilot/autopilot_leg.gd")

const STATE_NORMAL := 0
const STATE_DASH := 1
const STATE_WALL := 2
const STATE_LADDER := 3

const MAX_TICKS := 260


var grid: AutopilotGrid
var profile: MovementProfile
var dash_definition: Resource
var tick_rate := 120.0
## Abilities the simulated character actually owns. A planner that assumes a
## dash or a wall grab the player has not unlocked plans moves that cannot happen.
var dash_enabled := true
var climb_enabled := true

var _position := Vector2.ZERO
var _context: MovementContext
var _motor: CharacterMotor2D
var _intent: CharacterIntent
var _environment: CharacterEnvironmentSnapshot
var _state := STATE_NORMAL
var _dash_charge := true
var _dash_direction := Vector2.ZERO
var _dash_remaining := 0.0
var _dash_attack_remaining := 0.0
var _dash_refill_delay := 0.0
var _dash_just_started := false
var _wall_side := 0
var _wall_lockout := 0.0
var _wall_lockout_side := 0
var _force_move_x := 0.0
var _force_move_x_remaining := 0.0
var _climb_jump_window := 0.0
var _stamina := 110.0
var _ladder_jump_active := false
var _last_hit_wall := false
var _last_landed := false
var _left_ground := false


func configure(
	nav_grid: AutopilotGrid,
	movement_profile: MovementProfile,
	dash_ability: Resource = null,
	physics_tick_rate: float = 120.0
) -> void:
	grid = nav_grid
	profile = movement_profile
	dash_definition = dash_ability
	tick_rate = maxf(physics_tick_rate, 1.0)


func get_tick_delta() -> float:
	return 1.0 / tick_rate


## Only the moves the character has the abilities for.
func _is_available(action_name: StringName) -> bool:
	match action_name:
		&"dash", &"dash_jump", &"jump_dash":
			return dash_enabled
		&"wall_step", &"wall_jump", &"wall_climb_jump":
			return climb_enabled
	return true


func max_dash_charges() -> int:
	if dash_definition == null:
		return 0
	return maxi(0, int(dash_definition.get("max_charges")))


func dash_speed() -> float:
	return 0.0 if dash_definition == null else maxf(0.0, float(dash_definition.get("dash_speed")))


func dash_duration() -> float:
	return 0.0 if dash_definition == null else maxf(0.0, float(dash_definition.get("dash_duration")))


func dash_end_speed() -> float:
	return 0.0 if dash_definition == null else maxf(0.0, float(dash_definition.get("end_speed")))


func dash_attack_seconds() -> float:
	return (
		0.0 if dash_definition == null else maxf(0.0, float(dash_definition.get("dash_attack_seconds")))
	)


func dash_refill_seconds() -> float:
	return (
		0.0
		if dash_definition == null
		else maxf(0.0, float(dash_definition.get("refill_cooldown_seconds")))
	)


## Simulate one action from [param start_state]:
## `{position, velocity, mode, dash_charge, stamina, wall_side}`.
## Returns null when the action is impossible or fell out of the room.
## Simulate one action from [param start_state].
##
## The simulator keeps its body state in fields and writes [member
## AutopilotGrid.last_move_position] through the shared raster, so only one owner
## may be inside it at a time. [param owner] names the caller: the planner uses
## its own token, everyone else defaults to `external`. A caller that does not
## hold the lock gets `null` instead of a corrupted leg.
func simulate(start_state: Dictionary, action: Dictionary, owner: StringName = &"external") -> AutopilotLeg:
	if grid == null:
		return null
	if not grid.lock.try_acquire(owner):
		return null
	var leg := _simulate_locked(start_state, action)
	grid.lock.release(owner)
	return leg


func _simulate_locked(start_state: Dictionary, action: Dictionary) -> AutopilotLeg:
	if grid == null or profile == null or not grid.is_built():
		return null
	var action_name := StringName(action.get("name", &""))
	if not _is_available(action_name):
		return null
	_reset(start_state)
	var axis := float(action.get("axis", 0.0))
	var vertical := float(action.get("vertical", 0.0))
	var hold_ticks := int(action.get("hold_ticks", 30))
	var max_ticks := int(action.get("max_ticks", MAX_TICKS))
	var dash_direction := Vector2(action.get("dash_dir", Vector2.ZERO))
	var delay_ticks := int(action.get("delay_ticks", 18))
	var dash_ticks := int(dash_duration() * tick_rate) + 2
	var stall_window := 12
	var stall_position := _position
	var stall_start := 0
	var leg := LEG.new()
	leg.action = action_name
	leg.start_position = _position
	leg.start_velocity = _context.velocity
	leg.start_mode = int(start_state.get("mode", LEG.MODE_GROUND))
	leg.start_cell = grid.world_to_cell(_position + Vector2(0.0, 0.5))
	for tick: int in range(max_ticks):
		var jump_pressed := false
		var jump_held := false
		var frame_axis := axis
		var frame_vertical := 0.0
		var frame_dash := Vector2.ZERO
		match action_name:
			&"walk", &"fall":
				pass
			&"jump":
				jump_pressed = tick == 0
				jump_held = tick < hold_ticks
			&"dash":
				if tick == 0:
					frame_dash = dash_direction
			&"dash_jump":
				jump_pressed = tick == dash_ticks
				jump_held = tick >= dash_ticks and tick < dash_ticks + hold_ticks
			&"jump_dash":
				jump_pressed = tick == 0
				jump_held = tick < delay_ticks and tick < hold_ticks
				if tick == delay_ticks:
					frame_dash = dash_direction
			&"wall_step":
				frame_axis = float(_wall_side)
				frame_vertical = vertical
			&"wall_jump":
				frame_axis = -float(_wall_side)
				jump_pressed = tick == 0
				jump_held = tick < hold_ticks
			&"wall_climb_jump":
				if tick == 0:
					frame_axis = float(_wall_side)
					frame_vertical = -1.0
					jump_pressed = true
				elif tick < 30:
					# Rise clear of the wall before steering back over the lip.
					frame_axis = 0.0
					jump_held = true
				else:
					frame_axis = float(_wall_side)
					jump_held = tick < hold_ticks
			&"ladder":
				frame_vertical = vertical
		_tick(frame_axis, frame_vertical, jump_pressed, jump_held, frame_dash)
		leg.append_tick(
			frame_axis,
			frame_vertical,
			jump_pressed,
			jump_held,
			frame_dash,
			_position
		)
		if _position.y > _room_bottom() + 48.0:
			return null
		# A leg wedged in geometry neither lands nor moves: drop it instead of
		# handing the driver a long do-nothing script.
		if tick - stall_start >= stall_window:
			if _position.distance_to(stall_position) < 1.0:
				return null
			stall_position = _position
			stall_start = tick
		if _should_stop(action_name, action, tick):
			break
	if leg.frames == 0:
		return null
	_finish_leg(leg, action_name, action)
	if leg.end_cell == leg.start_cell and leg.end_mode == leg.start_mode:
		return null
	return leg


func _reset(start_state: Dictionary) -> void:
	_position = Vector2(start_state.get("position", Vector2.ZERO))
	_context = MOVEMENT_CONTEXT.new()
	_motor = CHARACTER_MOTOR.new()
	_intent = CHARACTER_INTENT.new()
	_environment = ENVIRONMENT.new() as CharacterEnvironmentSnapshot
	_context.reset(Vector2(start_state.get("velocity", Vector2.ZERO)))
	_state = STATE_NORMAL
	var mode := int(start_state.get("mode", LEG.MODE_GROUND))
	_wall_side = LEG.wall_side_for_mode(mode)
	if mode == LEG.MODE_WALL_LEFT or mode == LEG.MODE_WALL_RIGHT:
		_state = STATE_WALL
	elif mode == LEG.MODE_LADDER:
		_state = STATE_LADDER
	_dash_charge = bool(start_state.get("dash_charge", true))
	_stamina = float(start_state.get("stamina", float(profile.get("max_stamina"))))
	_dash_direction = Vector2.ZERO
	_dash_remaining = 0.0
	_dash_attack_remaining = 0.0
	_dash_refill_delay = 0.0
	_dash_just_started = false
	_wall_lockout = 0.0
	_wall_lockout_side = 0
	_force_move_x = 0.0
	_force_move_x_remaining = 0.0
	_climb_jump_window = 0.0
	_ladder_jump_active = false
	_last_hit_wall = false
	_last_landed = grid.is_supported(_position)
	_left_ground = false


## Per-tick input policy per action.
func _should_stop(action_name: StringName, action: Dictionary, tick: int) -> bool:
	match action_name:
		&"walk", &"fall":
			return _left_ground and _landed_now()
		&"jump":
			return _landed_now() or _state == STATE_WALL or _state == STATE_LADDER
		&"dash":
			var dash_ticks := int(dash_duration() * tick_rate) + 2
			if tick >= dash_ticks and (_landed_now() or _state == STATE_WALL or _state == STATE_LADDER):
				return true
			return false
		&"dash_jump":
			var jump_tick := int(dash_duration() * tick_rate) + 2
			return tick >= jump_tick and (_landed_now() or _state == STATE_LADDER)
		&"jump_dash":
			var delay_ticks := int(action.get("delay_ticks", 18)) + int(dash_duration() * tick_rate) + 2
			return tick >= delay_ticks and (_landed_now() or _state == STATE_LADDER)
		&"wall_step":
			if _landed_now():
				return true
			if _state != STATE_WALL:
				return true
			return tick + 1 >= int(action.get("ticks", 21))
		&"wall_jump", &"wall_climb_jump":
			if _landed_now():
				return true
			if _state == STATE_LADDER:
				return true
			# A wall jump that catches the far wall is finished once it grabs.
			return _state == STATE_WALL and tick > 1
		&"ladder":
			if not grid.is_on_ladder(_position) and _state != STATE_LADDER:
				return true
			return tick + 1 >= int(action.get("ticks", 14))
	return false


func _landed_now() -> bool:
	return _last_landed


func _finish_leg(leg: AutopilotLeg, _action_name: StringName, _action: Dictionary) -> void:
	if _state == STATE_WALL:
		leg.end_mode = LEG.MODE_WALL_LEFT if _wall_side < 0 else LEG.MODE_WALL_RIGHT
	elif _state == STATE_LADDER or grid.is_on_ladder(_position):
		leg.end_mode = LEG.MODE_LADDER
	elif _last_landed:
		leg.end_mode = LEG.MODE_GROUND
	else:
		leg.end_mode = LEG.MODE_AIR
	leg.end_position = _position
	leg.end_velocity = _context.velocity
	leg.end_cell = grid.world_to_cell(_position)
	if leg.end_mode == LEG.MODE_GROUND:
		# Landings snap to a nav foothold so the plan and the live player agree.
		var foothold := grid.find_standable_cell(_position, 1)
		if foothold != AutopilotGrid.INVALID_CELL:
			var foothold_position := grid.cell_to_world(foothold)
			if absf(foothold_position.y - _position.y) <= 5.0:
				_position = foothold_position
				leg.end_position = foothold_position
				leg.end_cell = foothold
		elif not grid.cell_is_standable(leg.end_cell):
			leg.end_mode = LEG.MODE_AIR
	elif leg.end_mode == LEG.MODE_LADDER:
		leg.end_cell = grid.world_to_cell(_position + Vector2(0.0, 0.5))
		_position = grid.cell_to_world(leg.end_cell)
		leg.end_position = _position
	elif leg.end_mode == LEG.MODE_WALL_LEFT or leg.end_mode == LEG.MODE_WALL_RIGHT:
		# Walls are climbed in whole rows; the horizontal offset to the face stays.
		leg.end_cell = grid.world_to_cell(_position + Vector2(0.0, 0.5))
		_position.y = float(leg.end_cell.y * AutopilotGrid.NAV_CELL_SIZE)
		leg.end_position = _position
	leg.dash_charge_after = _dash_charge or leg.end_mode == LEG.MODE_GROUND
	leg.stamina_after = _stamina


func _tick(
	axis: float,
	vertical: float,
	jump_pressed: bool,
	jump_held: bool,
	dash_dir: Vector2
) -> void:
	var dt := get_tick_delta()
	_intent.clear_transient()
	_intent.move_axis = axis
	_intent.vertical_axis = vertical
	_intent.jump_pressed = jump_pressed
	_intent.jump_held = jump_held
	_dash_attack_remaining = maxf(_dash_attack_remaining - dt, 0.0)
	_wall_lockout = maxf(_wall_lockout - dt, 0.0)
	if _wall_lockout <= 0.0:
		_wall_lockout_side = 0
	_dash_refill_delay = maxf(_dash_refill_delay - dt, 0.0)
	_force_move_x_remaining = maxf(_force_move_x_remaining - dt, 0.0)
	_capture_environment()
	_last_landed = _environment.grounded and _context.velocity.y >= -0.01
	if _state != STATE_DASH and not dash_dir.is_zero_approx() and _dash_charge and dash_enabled:
		_start_dash(dash_dir)
	var environment := _environment
	var handled := false
	if _state == STATE_DASH:
		_step_dash(dt)
		handled = true
	elif grid.is_on_ladder(_position):
		handled = _step_ladder(dt)
	elif _state == STATE_WALL:
		handled = _step_wall(environment, dt)
	elif _try_enter_wall(axis):
		handled = _step_wall(environment, dt)
	if not handled:
		_state = STATE_NORMAL
		_step_normal(environment, dt)
	_move(dt)
	_last_landed = grid.is_supported(_position) and _context.velocity.y >= -0.01
	if not _last_landed:
		_left_ground = true


func _capture_environment() -> void:
	var environment := _environment
	# `is_on_floor()` is only true while the character is not moving up, so a
	# rising jump does not hold ground acceleration for the first few pixels.
	environment.grounded = (
		_context.velocity.y >= -0.01 and grid.is_supported(_position)
	)
	environment.ceiling = false
	environment.floor_normal = Vector2.UP


func _start_dash(direction: Vector2) -> void:
	_dash_direction = _snap_direction(direction)
	_dash_remaining = maxf(0.01, dash_duration())
	_dash_attack_remaining = dash_attack_seconds()
	_dash_refill_delay = dash_refill_seconds()
	_dash_just_started = true
	_dash_charge = false
	_force_move_x_remaining = 0.0
	_climb_jump_window = 0.0
	_context.velocity = Vector2.ZERO
	_state = STATE_DASH


func _step_dash(dt: float) -> void:
	if _dash_just_started:
		_dash_just_started = false
		_context.velocity = Vector2.ZERO
		return
	_dash_remaining = maxf(_dash_remaining - dt, 0.0)
	_context.velocity = _dash_direction * dash_speed()
	if _dash_remaining <= 0.0:
		_context.velocity = _dash_direction * dash_end_speed()
		_state = STATE_NORMAL


func _step_normal(environment: CharacterEnvironmentSnapshot, dt: float) -> void:
	_motor.step(_context, _intent, environment, profile, dt)
	if _force_move_x_remaining > 0.0:
		_context.velocity.x = _force_move_x
	if _intent.jump_pressed and _try_advanced_jump(environment):
		_intent.jump_pressed = false
	_update_climb_jump_conversion(dt)
	if environment.grounded:
		_stamina = float(profile.get("max_stamina"))
		if _dash_refill_delay <= 0.0:
			_dash_charge = true


func _try_advanced_jump(environment: CharacterEnvironmentSnapshot) -> bool:
	if _dash_attack_remaining <= 0.0:
		return false
	if _dash_direction.y < -0.5:
		var wall_side := _find_wall()
		if wall_side == 0:
			return false
		_apply_wallbounce(-wall_side)
		return true
	if _dash_direction.y > 0.5 and not environment.grounded:
		return false
	if not (environment.grounded or _context.coyote_remaining > 0.0):
		return false
	var direction := 1.0 if _intent.move_axis >= 0.0 else -1.0
	_context.velocity = Vector2(float(profile.get("super_jump_speed")) * direction, 0.0)
	_context.velocity.y = float(profile.get("jump_speed"))
	_apply_jump_timers(_context.velocity.y)
	return true


func _apply_wallbounce(away: int) -> void:
	_context.velocity = Vector2(
		float(profile.get("wallbounce_speed")) * float(away),
		float(profile.get("wallbounce_jump_speed"))
	)
	_apply_jump_timers(_context.velocity.y, 0.25)
	_force_move_x = float(profile.get("wallbounce_speed")) * float(away)
	_force_move_x_remaining = float(profile.get("wall_jump_force_time"))
	_wall_lockout = float(profile.get("wall_grab_lockout"))
	_wall_lockout_side = -away
	_state = STATE_NORMAL


func _step_wall(environment: CharacterEnvironmentSnapshot, dt: float) -> bool:
	if _wall_side == 0 or environment.grounded:
		_state = STATE_NORMAL
		return false
	if not grid.has_wall(_position, _wall_side):
		_state = STATE_NORMAL
		return false
	if _intent.jump_pressed:
		if _intent.vertical_axis < -0.5 and _stamina > 0.0:
			_apply_climb_jump()
		else:
			_apply_wall_jump()
		return true
	if _intent.vertical_axis < -0.5:
		_context.velocity = Vector2(0.0, -float(profile.get("wall_climb_speed")))
		_stamina -= float(profile.get("stamina_climb_drain")) * dt
	elif _intent.vertical_axis > 0.5:
		_context.velocity = Vector2(0.0, float(profile.get("climb_down_speed")))
	else:
		_context.velocity = Vector2.ZERO
		_stamina -= float(profile.get("stamina_grab_drain")) * dt
	if _stamina <= 0.0:
		_stamina = 0.0
		_state = STATE_NORMAL
	return true


func _try_enter_wall(axis: float) -> bool:
	if not climb_enabled:
		return false
	if grid.is_supported(_position):
		return false
	var direction := 0
	if axis > 0.3:
		direction = 1
	elif axis < -0.3:
		direction = -1
	if direction == 0:
		return false
	if _wall_lockout > 0.0 and direction == _wall_lockout_side:
		return false
	if not grid.has_wall(_position, direction):
		return false
	_wall_side = direction
	_snap_to_wall(direction)
	_state = STATE_WALL
	_context.velocity = Vector2.ZERO
	if _stamina <= 0.0:
		_state = STATE_NORMAL
		return false
	return true


## Flush against the wall, matching the controller's grab snap so the planned
## wall column lines up with the live one.
func _snap_to_wall(side: int) -> void:
	for _step: int in range(4):
		var candidate := _position + Vector2(float(side), 0.0)
		if grid.has_wall(candidate, side) and not grid.box_hits(candidate):
			_position = candidate
		else:
			return


func _apply_wall_jump() -> void:
	var away := -_wall_side
	_context.velocity = Vector2(
		float(profile.get("wall_jump_speed")) * float(away),
		float(profile.get("jump_speed"))
	)
	_apply_jump_timers(_context.velocity.y)
	_force_move_x = float(profile.get("wall_jump_speed")) * float(away)
	_force_move_x_remaining = float(profile.get("wall_jump_force_time"))
	_wall_lockout = float(profile.get("wall_grab_lockout"))
	_wall_lockout_side = _wall_side
	_state = STATE_NORMAL


func _apply_climb_jump() -> void:
	_stamina = maxf(_stamina - float(profile.get("climb_jump_stamina")), 0.0)
	_context.velocity = Vector2(0.0, float(profile.get("jump_speed")))
	_apply_jump_timers(_context.velocity.y)
	_climb_jump_window = float(profile.get("climb_jump_convert_time"))
	_state = STATE_NORMAL


func _apply_jump_timers(vertical_speed: float, var_time: float = -1.0) -> void:
	_context.var_jump_remaining = (
		float(profile.get("var_jump_time")) if var_time < 0.0 else var_time
	)
	_context.var_jump_speed = vertical_speed
	_context.jump_buffer_remaining = 0.0
	_context.coyote_remaining = 0.0
	_context.just_jumped = true


func _update_climb_jump_conversion(dt: float) -> void:
	if _climb_jump_window <= 0.0:
		return
	if _intent.move_axis * float(_wall_side) < -0.3:
		var away := -_wall_side
		_context.velocity.x = float(profile.get("wall_jump_speed")) * float(away)
		_force_move_x = _context.velocity.x
		_force_move_x_remaining = float(profile.get("wall_jump_force_time"))
		_wall_lockout = float(profile.get("wall_grab_lockout"))
		_wall_lockout_side = _wall_side
		_climb_jump_window = 0.0
		return
	_climb_jump_window = maxf(_climb_jump_window - dt, 0.0)


func _step_ladder(dt: float) -> bool:
	if _intent.jump_pressed:
		_context.velocity = Vector2(_context.velocity.x, float(profile.get("jump_speed")))
		_context.just_jumped = true
		_context.jump_buffer_remaining = 0.0
		_context.coyote_remaining = 0.0
		_ladder_jump_active = true
		_state = STATE_NORMAL
		return true
	if _ladder_jump_active and _intent.jump_held and _context.velocity.y < 0.0:
		_context.velocity.y += float(profile.get("gravity")) * dt
		return true
	_ladder_jump_active = false
	var direction := Vector2(_intent.move_axis, _intent.vertical_axis)
	if direction.length_squared() > 1.0:
		direction = direction.normalized()
	_context.velocity = direction * float(profile.get("climb_speed"))
	_state = STATE_LADDER
	_stamina = float(profile.get("max_stamina"))
	return true


func _move(dt: float) -> void:
	var motion := _context.velocity * dt
	grid.move_box(_position, motion)
	if grid.last_move_hit_x and _state == STATE_DASH and absf(_dash_direction.y) < 0.5:
		# Mirror the controller's dash corner correction: a horizontal dash that
		# clips a lip slides up or down a few pixels instead of stopping.
		if _try_dash_corner(motion):
			return
	elif grid.last_move_hit_y and motion.y < 0.0:
		# Mirror the controller's upward corner correction: a head that clips a
		# ledge corner is nudged one pixel up and sideways instead of stopping.
		_try_upward_corner(motion)
	_position = grid.last_move_position
	if grid.last_move_hit_y:
		_context.velocity.y = 0.0
	if grid.last_move_hit_x:
		_context.velocity.x = 0.0


func _try_dash_corner(motion: Vector2) -> bool:
	var limit := maxi(1, int(profile.get("corner_correction")))
	for offset: int in range(1, limit + 1):
		for direction: int in [-1, 1]:
			var candidate := _position + Vector2(0.0, float(direction * offset))
			if grid.box_hits_margin(candidate, false):
				continue
			grid.move_box(candidate, motion)
			if not grid.last_move_hit_x:
				_position = grid.last_move_position
				return true
	return false


func _try_upward_corner(motion: Vector2) -> void:
	var limit := maxi(1, int(profile.get("corner_correction")))
	var first := 1 if _context.velocity.x >= 0.0 else -1
	for side: int in [first, -first]:
		for offset: int in range(1, limit + 1):
			# The controller lifts the body one pixel as part of the nudge.
			var candidate := _position + Vector2(float(side * offset), -1.0)
			if (
				grid.box_hits_margin(candidate, false)
				or grid.box_hits_margin(candidate + Vector2(0.0, motion.y), false)
			):
				continue
			_position = candidate
			grid.move_box(_position, Vector2(0.0, motion.y))
			return


func _snap_direction(direction: Vector2) -> Vector2:
	var snap := 45.0
	if dash_definition != null:
		snap = float(dash_definition.get("direction_snap_degrees"))
	var normalized := direction.normalized()
	if snap > 0.0 and snap < 360.0:
		var step := deg_to_rad(snap)
		normalized = Vector2.from_angle(roundf(normalized.angle() / step) * step)
		if absf(normalized.x) < 0.001:
			normalized.x = 0.0
		if absf(normalized.y) < 0.001:
			normalized.y = 0.0
	return normalized.normalized()


func _find_wall() -> int:
	for direction: int in [-1, 1]:
		if grid.has_wall(_position, direction):
			return direction
	return 0


func _room_bottom() -> float:
	return float(grid.nav_rect.end.y * AutopilotGrid.NAV_CELL_SIZE)
