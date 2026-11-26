class_name AutopilotDriver
extends RefCounted

## Plays a planned route by feeding one recorded input tick to the character each
## physics tick. It plugs into the character's input-source seam, so it works with
## any actor that exposes `set_input_source()` / `get_intent()`.
##
## The driver reports drift instead of correcting it: when the live position
## leaves the planned trajectory, the owner replans from the current state.

signal route_finished(reached: bool)
signal route_deviation(at_position: Vector2)

const CHARACTER_INTENT := preload("res://addons/platformer_kit/character/input/character_intent.gd")
const ROUTE := preload("res://addons/platformer_kit/character/autopilot/autopilot_route.gd")
const LEG := preload("res://addons/platformer_kit/character/autopilot/autopilot_leg.gd")

## Distance in pixels a live frame may drift from the plan before it replans.
const DEFAULT_TOLERANCE := 10.0
## A leg that finishes this far from the next leg's start triggers a replan
## instead of replaying inputs the character is no longer aligned with.
const DEFAULT_LEG_END_TOLERANCE := 9.0

var _actor: Node2D
var _base: RefCounted
var _route: AutopilotRoute
var _leg_index := 0
var _tick := 0
var _active := false
var _tolerance := DEFAULT_TOLERANCE
var _last_leg_label := ""
## Tick until which `jump_held` stays on, including the relaxation slack.
var _jump_hold_until := 0

## Diagnostics for the frame that tripped the drift check.
var last_deviation_leg := -1
var last_deviation_tick := -1
var last_deviation_action := ""
var last_expected := Vector2.ZERO
var last_actual := Vector2.ZERO
var last_leg_start := Vector2.ZERO
## Distance between where each leg planned to start and where the character
## actually stood when the leg began. Cleared with the route.
var leg_entry_errors: Array[float] = []
## Opt-in per-tick trace (planned vs live) used to diagnose drift.
var trace_enabled := false
var trace: Array[Dictionary] = []
const TRACE_LIMIT := 40
## A leg boundary whose live velocity differs from the plan by this much asks
## for a replan: the inputs of the next leg would be replayed for a body that is
## no longer moving the way the leg was simulated.
const VELOCITY_MISMATCH := 45.0
## Extra ticks a planned jump keeps the button held. The motor's variable-jump
## window clamps the result, so this only ever makes the live arc taller.
const JUMP_HOLD_SLACK := 4
## Extra ticks a jump leg may run while the body is still airborne.
const JUMP_LANDING_GRACE := 26


func _record_trace(
	leg: AutopilotLeg,
	tick: int,
	planned: Vector2,
	actual: Vector2,
	axis: float,
	state: int
) -> void:
	if not trace_enabled:
		return
	trace.append({
		"leg": _leg_index,
		"tick": tick,
		"action": leg.action_code(),
		"planned": planned,
		"actual": actual,
		"axis": axis,
		"state": state,
		"velocity": (_actor.velocity if _actor is CharacterBody2D else Vector2.ZERO),
	})
	if trace.size() > TRACE_LIMIT:
		trace.remove_at(0)


func configure(actor: Node2D, base_source: RefCounted = null) -> void:
	_actor = actor
	_base = base_source


func set_tolerance(value: float) -> void:
	_tolerance = maxf(value, 1.0)


func get_actor() -> Node2D:
	return _actor


## Start replaying [param route]; an empty route stops the driver.
func set_route(route: AutopilotRoute) -> void:
	_route = route
	_leg_index = 0
	_tick = 0
	_last_leg_label = ""
	leg_entry_errors.clear()
	_jump_hold_until = 0
	_active = route != null and not route.is_empty()


func stop() -> void:
	_active = false
	_route = null
	_leg_index = 0
	_tick = 0
	_jump_hold_until = 0


func is_active() -> bool:
	return _active


func get_progress() -> Dictionary:
	var leg := _current_leg()
	return {
		"leg": _leg_index,
		"leg_count": 0 if _route == null else _route.get_leg_count(),
		"action": "" if leg == null else String(leg.action),
		"label": "" if leg == null else leg.action_label(),
		"code": "" if leg == null else leg.action_code(),
		"tick": _tick,
		"frames": 0 if leg == null else leg.frames,
	}


## Input-source contract: one intent per physics tick.
##
## Jump/dash timing comes from the recorded script; legs finish as soon as their
## own goal is met, so a small model error never turns into a permanent drift.
func get_intent() -> CharacterIntent:
	if not _active or _actor == null:
		return _base_intent()
	while _active:
		var leg := _current_leg()
		if leg == null:
			return _base_intent()
		if _tick >= _hard_limit(leg):
			_advance_leg()
			continue
		if _tick >= 2 and _leg_reached(leg):
			_advance_leg()
			continue
		break
	var current := _current_leg()
	if current == null:
		return _base_intent()
	if _tick > 0:
		var expected := current.get_sample(_tick - 1)
		var drift := _drift_distance(current, expected, _actor.global_position)
		_record_trace(current, _tick - 1, expected, _actor.global_position, 0.0, _actor_state())
		if drift > _tolerance:
			var at_position := _actor.global_position
			last_deviation_leg = _leg_index
			last_deviation_tick = _tick - 1
			last_deviation_action = current.action_code()
			last_expected = expected
			last_actual = at_position
			last_leg_start = current.start_position
			stop()
			route_deviation.emit(at_position)
			return _base_intent()
	var intent := _decode(current, _tick)
	_last_leg_label = current.action_label()
	if trace_enabled and not trace.is_empty():
		trace[trace.size() - 1]["axis"] = intent.move_axis
	_tick += 1
	if _tick >= _hard_limit(current):
		_advance_leg()
	return intent


## PlayerMotionState value, for the trace: 0 normal, 1 dash, 3 wall grab.
func _actor_state() -> int:
	if _actor == null or not _actor.has_method("get_debug_state"):
		return -1
	var debug: Dictionary = _actor.call("get_debug_state")
	return int(debug.get("state", -1))


## Ladder and wall rows take as long as the character needs: hold the input for
## up to twice the planned time instead of dropping the climb mid-row.
func _hard_limit(leg: AutopilotLeg) -> int:
	if leg.action == &"ladder" or leg.action == &"wall_step":
		return leg.frames * 2
	if leg.action == &"jump" or leg.action == &"jump_dash" or leg.action == &"dash_jump":
		# The relaxed jump hold can stretch the arc a few ticks past the planned
		# landing. Wait for the body to touch down before the next leg starts from
		# a position it has not reached yet — but only when another leg follows.
		if _route != null and _leg_index + 1 < _route.get_leg_count():
			if _actor is CharacterBody2D and not (_actor as CharacterBody2D).is_on_floor():
				return leg.frames + JUMP_LANDING_GRACE
	return leg.frames


## True when the leg's own objective is already met.
func _leg_reached(leg: AutopilotLeg) -> bool:
	if _actor == null:
		return false
	if (
		leg.end_mode == LEG.MODE_LADDER
		and _actor.has_method("is_on_ladder")
		and bool(_actor.call("is_on_ladder"))
	):
		return true
	if leg.action == &"walk":
		return absf(_actor.global_position.x - leg.end_position.x) <= 2.0
	if leg.action == &"ladder" or leg.action == &"wall_step":
		# Hold the climb until the body reaches the planned row.
		var row := floori(_actor.global_position.y / float(AutopilotGrid.NAV_CELL_SIZE))
		return row == leg.end_cell.y
	# Back on the floor with a foothold leg: the move is over, even if the model
	# gave it more frames. Dash legs wait for their own dash window first.
	var min_ticks := 2
	match leg.action:
		&"dash", &"dash_jump", &"jump_dash":
			min_ticks = 22
	if (
		_tick >= min_ticks
		and _actor.has_method("is_on_floor")
		and bool(_actor.call("is_on_floor"))
	):
		# Standing on the floor means this leg is over, whatever the model
		# expected; a mismatched next leg will ask for a replan.
		return true
	return false


func _advance_leg() -> void:
	_leg_index += 1
	_tick = 0
	if _route == null or _leg_index >= _route.get_leg_count():
		stop()
		route_finished.emit(true)
		return
	if _actor == null:
		return
	var next_leg: AutopilotLeg = _route.legs[_leg_index]
	var entry_error := _actor.global_position.distance_to(next_leg.start_position)
	leg_entry_errors.append(entry_error)
	var velocity_error := 0.0
	if _actor is CharacterBody2D:
		velocity_error = (_actor as CharacterBody2D).velocity.distance_to(next_leg.start_velocity)
	# A ladder leg starts from wherever the body hangs; its planned start height
	# is a whole cell, and its start velocity is a modelling choice, so neither is
	# a reason to throw the route away.
	var on_ladder := next_leg.start_mode == LEG.MODE_LADDER
	if on_ladder:
		entry_error = 0.0
		velocity_error = 0.0
	if entry_error > DEFAULT_LEG_END_TOLERANCE or velocity_error > VELOCITY_MISMATCH:
		var at_position := _actor.global_position
		last_deviation_leg = _leg_index
		last_deviation_tick = 0
		last_deviation_action = next_leg.action_code()
		last_expected = next_leg.start_position
		last_actual = at_position
		stop()
		route_deviation.emit(at_position)


func _current_leg() -> AutopilotLeg:
	if _route == null or _leg_index < 0 or _leg_index >= _route.get_leg_count():
		return null
	return _route.legs[_leg_index]


func _decode(leg: AutopilotLeg, tick: int) -> CharacterIntent:
	var frame := leg.get_intent(mini(tick, maxi(leg.frames - 1, 0)))
	var intent := CHARACTER_INTENT.new() as CharacterIntent
	intent.move_axis = float(frame.get("axis", 0.0))
	intent.vertical_axis = float(frame.get("vertical", 0.0))
	intent.jump_pressed = bool(frame.get("jump_pressed", false))
	intent.jump_held = bool(frame.get("jump_held", false))
	intent.jump_released = false
	intent.fast_fall = false
	if intent.jump_pressed:
		_extend_jump_hold(leg, tick)
	if tick < _jump_hold_until:
		# One-sided relaxation: hold a few ticks longer than planned, so the live
		# jump is never *lower* than the arc A* counted on.
		intent.jump_held = true
	var dash_direction := Vector2(frame.get("dash_dir", Vector2.ZERO))
	if not dash_direction.is_zero_approx():
		# The dash reads its direction from the axes, so the diagonal has to be in
		# the intent: pressing dash alone would dash horizontally.
		intent.press_action(&"dash")
		intent.move_axis = signf(dash_direction.x)
		intent.vertical_axis = signf(dash_direction.y)
	return intent


## Remember how long this jump keeps the button, plus the slack. The motor clamps
## the rise to the profile's variable-jump window, so extra ticks cannot make the
## jump taller than the character can actually go.
func _extend_jump_hold(leg: AutopilotLeg, tick: int) -> void:
	var planned := 0
	var probe := tick
	while probe < leg.frames and bool(leg.get_intent(probe).get("jump_held", false)):
		planned += 1
		probe += 1
	_jump_hold_until = maxi(_jump_hold_until, tick + planned + JUMP_HOLD_SLACK)


## Distance between the live body and the planned sample, ignoring the one
## direction the relaxation deliberately overshoots: a jump that rises *higher*
## than planned is still on plan, because the extra hold can only add height.
func _drift_distance(leg: AutopilotLeg, expected: Vector2, actual: Vector2) -> float:
	var delta := actual - expected
	if delta.y < 0.0 and leg.start_velocity.y <= 0.0:
		# A leg that starts by rising (a jump) may end up higher than planned:
		# the relaxed hold only ever adds height, so that is still on plan.
		delta.y = 0.0
	if delta.y != 0.0 and leg.action == &"ladder":
		# Ladder nodes are quantized to whole cells while the live body hangs
		# wherever it grabbed, so the height disagreement is the plan's grid, not
		# the character going off route.
		delta.y = 0.0
	return delta.length()


func _base_intent() -> CharacterIntent:
	if _base != null and _base.has_method("get_intent"):
		var intent: CharacterIntent = _base.call("get_intent") as CharacterIntent
		if intent != null:
			return intent
	return CHARACTER_INTENT.new() as CharacterIntent


func describe() -> String:
	if _route == null:
		return "无路线"
	return "%s %d/%d" % [_last_leg_label, _leg_index + 1, _route.get_leg_count()]
