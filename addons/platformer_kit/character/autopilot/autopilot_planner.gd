class_name AutopilotPlanner
extends RefCounted

## A* over (cell, mode) nodes. Nodes are rest states on the navigation grid
## (foothold, ladder, wall face) plus transient air states. Edges are movement
## legs produced by [AutopilotMotion], so every planned step is replayable.

const LEG := preload("res://addons/platformer_kit/character/autopilot/autopilot_leg.gd")
const ROUTE := preload("res://addons/platformer_kit/character/autopilot/autopilot_route.gd")

const MODE_GROUND := LEG.MODE_GROUND
const MODE_AIR := LEG.MODE_AIR
const MODE_WALL_LEFT := LEG.MODE_WALL_LEFT
const MODE_WALL_RIGHT := LEG.MODE_WALL_RIGHT
const MODE_LADDER := LEG.MODE_LADDER

const MAX_EXPANSIONS := 5200
const TIME_BUDGET_MS := 8000
## Lock owner token the search uses while it drives the shared simulator.
const OWNER := &"planner"
const GOAL_TOLERANCE_CELLS := 1
## How close the body has to be to the goal cell's origin to count as arrived.
## Footholds snap to that origin, so a real landing is within a pixel or two.
const GOAL_POSITION_TOLERANCE := 6.0
const HEURISTIC_WEIGHT := 1.7
## Frames added per cell of missing head/elbow room at a landing, used only to
## order the search. Off by default: the benchmark shows it turns a 19-leg crawl
## into a 5-leg clean route, but on one deep room it costs reachability inside the
## expansion budget, so it stays opt-in until that is solved.
var stability_bias := 0.0
## Upper bound on the stability weight a node can carry, in frames. It keeps the
## preference a tie-break instead of a cost that could push the goal out of the
## expansion budget on a deep route.
const STABILITY_CAP := 24.0
const STABILITY_CLEARANCE_CELLS := 3
const FASTEST_SPEED := 330.0
const MAX_WALK_TICKS := 64

## Jump hold lengths in physics ticks: tap, medium, full.
const JUMP_HOLDS: Array[int] = [3, 12, 26]
const WALL_STAMINA_BUCKET := 25.0
const JUMP_MAX_TICKS := 170
const LEAP_MAX_TICKS := 200
const FALL_MAX_TICKS := 200

var grid: AutopilotGrid
var motion: AutopilotMotion
var tick_rate := 120.0

var _goal_cell := Vector2i.ZERO
var _goal_position := Vector2.ZERO
var _open_f: Array[float] = []
var _open_key: Array[int] = []
var _best_g: Dictionary = {}
var _parent: Dictionary = {}
var _parent_key: Dictionary = {}
var _states: Dictionary = {}
var _closed: Dictionary = {}
var _expansions := 0
var _deadline_ms := 0
var _tick_delta := 0.008333
## Simulated legs survive between plans: a replan from a nearby cell reuses the
## exact same arcs instead of re-running the simulator. Only ground starts are
## cached, because their state is quantized to a cell origin.
var _leg_cache: Dictionary = {}
const LEG_CACHE_LIMIT := 3000


func configure(nav_grid: AutopilotGrid, motion_sim: AutopilotMotion) -> void:
	grid = nav_grid
	motion = motion_sim
	tick_rate = motion_sim.tick_rate if motion_sim != null else 120.0
	_tick_delta = 1.0 / tick_rate
	_leg_cache.clear()


## Plan from a live character state to [param goal_world]. Returns an empty route
## when the goal is unreachable inside the navigable region.
##
## The search holds the raster lock for its whole run: it drives one simulator
## instance, so an outside probe must not run it at the same time.
func plan(start_state: Dictionary, goal_world: Vector2) -> AutopilotRoute:
	var route := ROUTE.new()
	if grid == null or motion == null or not grid.is_built():
		return route
	if not grid.lock.try_acquire(OWNER):
		push_warning("autopilot: planner busy, refusing to plan over another owner")
		return route
	var planned := _plan_locked(start_state, goal_world)
	grid.lock.release(OWNER)
	return planned


func _plan_locked(start_state: Dictionary, goal_world: Vector2) -> AutopilotRoute:
	var route := ROUTE.new()
	if grid == null or motion == null or not grid.is_built():
		return route
	_reset_search()
	_goal_position = goal_world
	_goal_cell = grid.find_goal_cell(goal_world, 10)
	if _goal_cell == AutopilotGrid.INVALID_CELL:
		return route
	var start := {
		"position": Vector2(start_state.get("position", Vector2.ZERO)),
		"velocity": Vector2(start_state.get("velocity", Vector2.ZERO)),
		"mode": int(start_state.get("mode", MODE_GROUND)),
		"dash_charge": bool(start_state.get("dash_charge", true)),
		"stamina": float(start_state.get("stamina", 110.0)),
		"g": 0.0,
	}
	if start.mode == MODE_GROUND:
		var snapped := grid.find_standable_cell(start.position, 1)
		if snapped != AutopilotGrid.INVALID_CELL:
			start.position = grid.cell_to_world(snapped)
	# Air, wall and ladder starts keep their exact position: the first leg has to
	# continue from where the character actually is.
	start["cell"] = (
		grid.find_standable_cell(start.position, 1)
		if start.mode == MODE_GROUND
		else grid.world_to_cell(start.position)
	)
	if start.cell == AutopilotGrid.INVALID_CELL or not grid.has_cell(start.cell):
		return route
	var start_key := _node_key(start.cell, start.mode, _flag(start))
	start["key"] = start_key
	_best_g[start_key] = 0.0
	_states[start_key] = start
	_push_open(start_key, _heuristic(start.cell))
	_deadline_ms = Time.get_ticks_msec() + TIME_BUDGET_MS
	while not _open_key.is_empty() and _expansions < MAX_EXPANSIONS:
		if Time.get_ticks_msec() > _deadline_ms:
			break
		var key := _pop()
		if _closed.has(key):
			continue
		_closed[key] = true
		_expansions += 1
		if not _states.has(key):
			continue
		var state: Dictionary = _states[key]
		if _is_goal(state):
			return _build_route(key, start.position)
		_expand(state)
	return route


func get_last_expansions() -> int:
	return _expansions


func _reset_search() -> void:
	_open_f.clear()
	_open_key.clear()
	_best_g.clear()
	_parent.clear()
	_parent_key.clear()
	_states.clear()
	_closed.clear()
	_expansions = 0


func _expand(state: Dictionary) -> void:
	var cell: Vector2i = state.cell
	var mode: int = state.mode
	if mode == MODE_GROUND:
		_add_walk_neighbors(state)
		if grid.cell_is_ladder(cell):
			_push_leg(state, {"name": &"ladder", "vertical": 0.0, "ticks": 2})
		for axis: float in [-1.0, 0.0, 1.0]:
			if not grid.box_hits(Vector2(state.position) + Vector2(0.0, -1.0)):
				for hold: int in JUMP_HOLDS:
					_push_leg(
						state,
						{"name": &"jump", "axis": axis, "hold_ticks": hold, "max_ticks": JUMP_MAX_TICKS}
					)
			if axis != 0.0 and not grid.cell_is_standable(cell + Vector2i(int(axis), 0)):
				# Stepping off a ledge. On flat ground the walk chain covers the
				# move; a "fall" there is a long blind walk that A* happily picks
				# and that walks straight into the first 1-cell step it meets.
				_push_leg(state, {"name": &"fall", "axis": axis, "max_ticks": FALL_MAX_TICKS})
		_push_dashes(state, true, Vector2(state.position))
	elif mode == MODE_AIR:
		for axis: float in [-1.0, 0.0, 1.0]:
			_push_leg(state, {"name": &"fall", "axis": axis, "max_ticks": FALL_MAX_TICKS})
		_push_dashes(state, bool(state.dash_charge), Vector2(state.position))
	elif mode == MODE_WALL_LEFT or mode == MODE_WALL_RIGHT:
		if motion == null or not motion.climb_enabled:
			return
		var side := LEG.wall_side_for_mode(mode)
		var bucket := _stamina_bucket(float(state.stamina))
		if bucket > 0:
			_push_leg(state, {"name": &"wall_step", "vertical": -1.0, "ticks": 22})
		_push_leg(state, {"name": &"wall_step", "vertical": 1.0, "ticks": 11})
		_push_leg(state, {"name": &"wall_jump", "max_ticks": 200})
		if bucket > 1:
			_push_leg(state, {"name": &"wall_climb_jump", "max_ticks": 200})
		_push_leg(state, {"name": &"fall", "axis": -float(side), "max_ticks": 220})
	elif mode == MODE_LADDER:
		_push_leg(state, {"name": &"ladder", "vertical": -1.0, "ticks": 14})
		_push_leg(state, {"name": &"ladder", "vertical": 1.0, "ticks": 14})
		for axis: float in [-1.0, 1.0]:
			# Long enough to cross a cell at the ladder's slow horizontal speed;
			# a shorter leg ends inside the same cell and is dropped as a no-op.
			_push_leg(state, {"name": &"ladder", "axis": axis, "vertical": 0.0, "ticks": 26})
		_push_leg(state, {"name": &"jump", "axis": 0.0, "hold_ticks": 26, "max_ticks": 200})


func _push_dashes(state: Dictionary, allow_followups: bool, origin: Vector2) -> void:
	if motion == null or not motion.dash_enabled:
		return
	if not bool(state.dash_charge):
		return
	for direction: Vector2 in LEG.DASH_DIRECTIONS:
		# A dash that starts inside a wall cannot move; skip the simulation.
		if grid.box_hits(origin + direction * 2.0):
			continue
		var axis := signf(direction.x)
		_push_leg(state, {"name": &"dash", "axis": axis, "dash_dir": direction, "max_ticks": LEAP_MAX_TICKS})
		if not allow_followups:
			continue
		_push_leg(
			state,
			{"name": &"dash_jump", "axis": axis, "dash_dir": direction, "max_ticks": LEAP_MAX_TICKS}
		)
		_push_leg(
			state,
			{
				"name": &"jump_dash",
				"axis": axis,
				"dash_dir": direction,
				"delay_ticks": 18,
				"hold_ticks": 26,
				"max_ticks": LEAP_MAX_TICKS,
			}
		)


func _add_walk_neighbors(state: Dictionary) -> void:
	var cell: Vector2i = state.cell
	for offset: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0)]:
		var neighbor := cell + offset
		if not grid.cell_is_standable(neighbor):
			continue
		_add_walk_leg(state, neighbor, float(offset.x))


func _add_walk_leg(state: Dictionary, neighbor: Vector2i, axis: float) -> void:
	var start_position := grid.cell_to_world(state.cell)
	var target_x := grid.cell_to_world(neighbor).x
	var velocity := float(Vector2(state.velocity).x)
	var leg := LEG.new()
	leg.action = &"walk"
	leg.start_position = start_position
	leg.start_velocity = Vector2(state.velocity)
	leg.start_mode = MODE_GROUND
	leg.start_cell = state.cell
	var position := start_position
	var max_speed := 100.0
	var acceleration := 1000.0
	if motion != null and motion.profile != null:
		max_speed = float(motion.profile.get("max_speed"))
		acceleration = float(motion.profile.get("ground_acceleration"))
	for _tick: int in range(MAX_WALK_TICKS):
		velocity = move_toward(velocity, axis * max_speed, acceleration * _tick_delta)
		position.x += velocity * _tick_delta
		# The straight line has to be clear, or the live body would stop at a lip
		# the raster knows about but this kinematic chain does not.
		if grid.box_hits_margin(position, false):
			return
		leg.append_tick(axis, 0.0, false, false, Vector2.ZERO, position)
		if absf(position.x - target_x) <= 1.0:
			break
	if absf(position.x - target_x) > 1.0:
		return
	leg.end_position = position
	leg.end_velocity = Vector2(velocity, 0.0)
	leg.end_mode = MODE_GROUND
	leg.end_cell = neighbor
	leg.dash_charge_after = true
	leg.stamina_after = float(state.stamina)
	_store(state, leg)


func _push_leg(state: Dictionary, action: Dictionary) -> void:
	if int(state.mode) == MODE_GROUND:
		# Only ground states are quantized enough to cache: the same cell, the
		# same velocity and the same action replay into the same leg.
		var cache_key := "%d|%d|%s" % [
			int(state.key),
			_action_signature(action),
			str(state.velocity),
		]
		if _leg_cache.has(cache_key):
			var cached = _leg_cache[cache_key]
			if cached != null:
				_store(state, cached as AutopilotLeg)
			return
		var leg := motion.simulate(state, action, OWNER)
		if _leg_cache.size() >= LEG_CACHE_LIMIT:
			_leg_cache.clear()
		_leg_cache[cache_key] = leg
		if leg != null:
			_store(state, leg)
		return
	var fresh := motion.simulate(state, action, OWNER)
	if fresh != null:
		_store(state, fresh)


func _action_signature(action: Dictionary) -> int:
	var dash_direction := Vector2(action.get("dash_dir", Vector2.ZERO))
	var signature := String(action.get("name", "")).hash() & 0xFFFF
	signature = signature * 7 + int(roundf(float(action.get("axis", 0.0)) * 2.0)) + 3
	signature = signature * 9 + int(roundf(dash_direction.x * 2.0)) + 3
	signature = signature * 9 + int(roundf(dash_direction.y * 2.0)) + 3
	signature = signature * 7 + int(action.get("hold_ticks", 0))
	signature = signature * 7 + int(roundf(float(action.get("vertical", 0.0)) * 2.0)) + 3
	signature = signature * 7 + int(action.get("ticks", 0)) + 1
	signature = signature * 7 + int(action.get("delay_ticks", 0)) + 1
	signature = signature * 7 + clampi(int(action.get("max_ticks", 0)) / 32, 0, 12)
	return signature & 0x7FFFF


## Soft preference, not a constraint: a landing that sits close to a wall or a
## ceiling costs extra frames, so among equally feasible routes A* picks the one
## with room to spare. It never rejects a leg, so reachability is unchanged.
func _stability_cost(end_mode: int, end_cell: Vector2i) -> float:
	if stability_bias <= 0.0:
		return 0.0
	if end_mode != MODE_GROUND and end_mode != MODE_LADDER:
		return 0.0
	var clearance := grid.cell_clearance(end_cell, STABILITY_CLEARANCE_CELLS)
	var missing := float(STABILITY_CLEARANCE_CELLS - clearance)
	return stability_bias * missing


## Mean air around the cells a route lands on, in nav cells (higher is calmer).
func route_stability(route: AutopilotRoute) -> float:
	if route == null or route.is_empty():
		return 0.0
	var total := 0.0
	for leg: AutopilotLeg in route.legs:
		total += float(grid.cell_clearance(leg.end_cell, STABILITY_CLEARANCE_CELLS))
	return total / float(route.get_leg_count())


func _store(state: Dictionary, leg: AutopilotLeg) -> void:
	var end_cell := leg.end_cell
	var end_mode := leg.end_mode
	if end_mode != MODE_AIR and not grid.has_cell(end_cell):
		return
	if end_mode == MODE_AIR and not grid.cell_is_free(end_cell):
		return
	if end_mode == MODE_GROUND and not grid.cell_is_standable(end_cell):
		return
	if end_mode == MODE_LADDER and not grid.cell_is_ladder(end_cell):
		return
	var key := _node_key(end_cell, end_mode, _flag_for(leg))
	# First state wins: a node's children were simulated from the state that was
	# stored with it, so replacing that state later would make the route jump
	# between positions the legs do not connect.
	if _best_g.has(key):
		return
	var g: float = float(state.g) + float(leg.frames)
	# The stability term only orders the search and is capped, so it can break
	# near-ties without moving the goal out of reach: `g` stays pure frames.
	var calm: float = minf(
		float(state.get("calm", 0.0)) + _stability_cost(end_mode, end_cell),
		STABILITY_CAP
	)
	_best_g[key] = g
	_parent[key] = leg
	_parent_key[key] = state.key
	_states[key] = {
		"position": leg.end_position,
		"velocity": leg.end_velocity,
		"mode": end_mode,
		"dash_charge": leg.dash_charge_after,
		"stamina": leg.stamina_after,
		"g": g,
		"calm": calm,
		"cell": end_cell,
		"key": key,
	}
	if _closed.has(key):
		return
	_push_open(key, g + calm + _heuristic(end_cell))


func _is_goal(state: Dictionary) -> bool:
	var cell: Vector2i = state.cell
	if int(state.mode) != MODE_GROUND and int(state.mode) != MODE_LADDER:
		return false
	if (
		absi(cell.x - _goal_cell.x) > GOAL_TOLERANCE_CELLS
		or absi(cell.y - _goal_cell.y) > GOAL_TOLERANCE_CELLS
	):
		return false
	# Cell tolerance alone would accept a character hanging a cell away on a
	# ladder; the body has to actually be at the goal position.
	return (
		Vector2(state.position).distance_to(grid.cell_to_world(_goal_cell))
		<= GOAL_POSITION_TOLERANCE
	)


func _build_route(goal_key: int, start_position: Vector2) -> AutopilotRoute:
	var route := ROUTE.new()
	route.start_position = start_position
	route.goal_cell = _goal_cell
	route.goal_position = _goal_position
	var chain: Array[AutopilotLeg] = []
	var key := goal_key
	var guard := 0
	while _parent.has(key) and guard < 512:
		guard += 1
		chain.push_front(_parent[key] as AutopilotLeg)
		if not _parent_key.has(key):
			break
		key = int(_parent_key[key])
	for leg: AutopilotLeg in chain:
		route.append_leg(leg)
	return route


func _heuristic(cell: Vector2i) -> float:
	var dx := absf(float(cell.x - _goal_cell.x)) * float(AutopilotGrid.NAV_CELL_SIZE)
	var dy := absf(float(cell.y - _goal_cell.y)) * float(AutopilotGrid.NAV_CELL_SIZE)
	return sqrt(dx * dx + dy * dy) / FASTEST_SPEED * tick_rate * HEURISTIC_WEIGHT


func _flag(state: Dictionary) -> int:
	if int(state.mode) == MODE_AIR:
		return 1 if bool(state.dash_charge) else 0
	if int(state.mode) == MODE_WALL_LEFT or int(state.mode) == MODE_WALL_RIGHT:
		return _stamina_bucket(float(state.stamina))
	return 0


func _flag_for(leg: AutopilotLeg) -> int:
	if leg.end_mode == MODE_AIR:
		return 1 if leg.dash_charge_after else 0
	if leg.end_mode == MODE_WALL_LEFT or leg.end_mode == MODE_WALL_RIGHT:
		return _stamina_bucket(leg.stamina_after)
	return 0


func _stamina_bucket(stamina: float) -> int:
	return clampi(int(stamina / WALL_STAMINA_BUCKET), 0, 4)


func _node_key_for_cell(cell: Vector2i) -> int:
	return _node_key(cell, MODE_GROUND, 0)


func _node_key(cell: Vector2i, mode: int, flag: int) -> int:
	var local := cell - grid.nav_rect.position
	var index := local.y * grid.nav_rect.size.x + local.x
	return ((index * 8 + mode) * 8 + flag)


func _pop() -> int:
	var last := _open_key.size() - 1
	var key: int = _open_key[0]
	_open_key[0] = _open_key[last]
	_open_f[0] = _open_f[last]
	_open_key.resize(last)
	_open_f.resize(last)
	var index := 0
	while true:
		var left := index * 2 + 1
		var right := left + 1
		var smallest := index
		if left < _open_f.size() and _open_f[left] < _open_f[smallest]:
			smallest = left
		if right < _open_f.size() and _open_f[right] < _open_f[smallest]:
			smallest = right
		if smallest == index:
			break
		var swap_f := _open_f[index]
		_open_f[index] = _open_f[smallest]
		_open_f[smallest] = swap_f
		var swap_key := _open_key[index]
		_open_key[index] = _open_key[smallest]
		_open_key[smallest] = swap_key
		index = smallest
	return key


func _push_open(key: int, priority: float) -> void:
	_open_key.append(key)
	_open_f.append(priority)
	var index := _open_key.size() - 1
	while index > 0:
		var parent_index := (index - 1) / 2
		if _open_f[parent_index] <= _open_f[index]:
			break
		var swap_f := _open_f[index]
		_open_f[index] = _open_f[parent_index]
		_open_f[parent_index] = swap_f
		var swap_key := _open_key[index]
		_open_key[index] = _open_key[parent_index]
		_open_key[parent_index] = swap_key
		index = parent_index
