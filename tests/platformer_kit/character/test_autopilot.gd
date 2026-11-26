extends Node

## Autopilot solver tests: navigation grid, the movement simulator, A* routing
## and input replay. Every fixture is a synthetic ASCII map, so the solver is
## proven without a physics world (the live raster is verified by a playtest).

const GRID := preload("res://addons/platformer_kit/character/autopilot/autopilot_grid.gd")
const MOTION := preload("res://addons/platformer_kit/character/autopilot/autopilot_motion.gd")
const PLANNER := preload("res://addons/platformer_kit/character/autopilot/autopilot_planner.gd")
const DRIVER := preload("res://addons/platformer_kit/character/autopilot/autopilot_driver.gd")
const LEG := preload("res://addons/platformer_kit/character/autopilot/autopilot_leg.gd")
const ROUTE := preload("res://addons/platformer_kit/character/autopilot/autopilot_route.gd")
const PROFILE := preload("res://addons/platformer_kit/character/resources/movement_profile.gd")
const DASH_DEFINITION := preload(
	"res://addons/platformer_kit/abilities/dash/dash_ability_definition.gd"
)

const OPEN_ROWS: Array[String] = [
	"........................................",
	"........................................",
	"........................................",
	"........................................",
	"........................................",
	"........................................",
	"........................................",
	"########################################",
	"########################################",
]

const GAP_ROWS: Array[String] = [
	"........................................",
	"........................................",
	"........................................",
	"........................................",
	"........................................",
	"........................................",
	"####........####........................",
	"####........####........................",
	"########################################",
]

const LEDGE_ROWS: Array[String] = [
	"........................................",
	"........................................",
	"........................................",
	"..........................####..........",
	"..........................####..........",
	"........................................",
	"........................................",
	"########################################",
	"########################################",
]

const LADDER_ROWS: Array[String] = [
	"........................................",
	"........................................",
	"........................................",
	"....................L...................",
	"....................L######.............",
	"....................L...................",
	"....................L...................",
	"....................L...................",
	"....................L...................",
	"....................L...................",
	"....................L...................",
	"....................L...................",
	"########################################",
]

const WIDE_GAP_ROWS: Array[String] = [
	"........................................",
	"........................................",
	"........................................",
	"........................................",
	"........................................",
	"........................................",
	"####................####................",
	"####................####................",
	"########################################",
]

const WALL_ROWS: Array[String] = [
	"........................................",
	"........................................",
	"........................................",
	"..............##########................",
	"..............##########................",
	"..............##########................",
	"..............##########................",
	"..............##########................",
	"..............##########................",
	"..............##########................",
	"..............##########................",
	"..............##########................",
	"..............##########................",
	"..............##########................",
	"..............##########................",
	"########################################",
]

const ONE_WAY_ROWS: Array[String] = [
	"........................................",
	"........................................",
	"........................................",
	"........................................",
	"........................................",
	"........................................",
	"...............------...................",
	"........................................",
	"########################################",
]

## Flat corridor for the shared-simulator lock contract.
const LOCK_ROWS: Array[String] = [
	"............",
	"............",
	"............",
	"............",
	"............",
	"............",
	"............",
	"############",
]

## Flat corridor with a low ceiling above the middle: hugging it is cramped.
const STAIR_ROWS: Array[String] = [
	"............",
	"............",
	"............",
	"....######..",
	"............",
	"............",
	"............",
	"############",
]

const SEALED_ROWS: Array[String] = [
	"........................................",
	"........................................",
	"........................................",
	"........................................",
	"........................................",
	"........................................",
	".............############...............",
	".............#..........#...............",
	".............#..........#...............",
	".............#..........#...............",
	".............#..........#...............",
	".............#..........#...............",
	"----------------------------------------",
	".............#..........#...............",
	".............#..........#...............",
	"########################################",
]


func run() -> Array[String]:
	var failures: Array[String] = []
	failures.append_array(_run_case(GridCase.new()))
	failures.append_array(_run_case(MotionCase.new()))
	failures.append_array(_run_case(PlannerCase.new()))
	failures.append_array(_run_case(DriverCase.new()))
	failures.append_array(_run_one_way_case())
	failures.append_array(_run_lock_case())
	failures.append_array(_run_stability_case())
	return failures


## The stability preference must be a tie-break, not a feasibility change: the
## biased planner has to find a route at least as calm as the unbiased one, and
## the same route must stay reachable.
func _run_stability_case() -> Array[String]:
	var failures: Array[String] = []
	for rows: Array[String] in [LOCK_ROWS, STAIR_ROWS]:
		var plain := _plan_with_bias(rows, 0.0)
		var calm := _plan_with_bias(rows, 4.0)
		if plain.get("route") == null or (plain.route as AutopilotRoute).is_empty():
			failures.append("the unbiased planner found no route")
			continue
		if calm.get("route") == null or (calm.route as AutopilotRoute).is_empty():
			failures.append("the biased planner lost a reachable route")
			continue
		if float(calm.stability) + 0.001 < float(plain.stability):
			failures.append(
				"the biased route was calmer-free (%.2f < %.2f)"
				% [float(calm.stability), float(plain.stability)]
			)
	return failures


func _plan_with_bias(rows: Array[String], bias: float) -> Dictionary:
	var nav := GRID.new() as AutopilotGrid
	nav.build_from_rows(rows)
	var sim := MOTION.new() as AutopilotMotion
	sim.configure(nav, PROFILE.new(), DASH_DEFINITION.new(), 120.0)
	var planner := PLANNER.new() as AutopilotPlanner
	planner.configure(nav, sim)
	planner.stability_bias = bias
	var start := nav.find_standable_cell(nav.cell_to_world(Vector2i(2, 6)), 5)
	var goal := nav.find_standable_cell(nav.cell_to_world(Vector2i(9, 6)), 5)
	if start == AutopilotGrid.INVALID_CELL or goal == AutopilotGrid.INVALID_CELL:
		return {"route": null, "stability": 0.0}
	var route = planner.plan(
		{
			"position": nav.cell_to_world(start),
			"velocity": Vector2.ZERO,
			"mode": 0,
			"dash_charge": true,
			"stamina": 110.0,
		},
		nav.cell_to_world(goal)
	)
	return {"route": route, "stability": planner.route_stability(route)}


## The raster, simulator and planner are shared between the tool, its worker
## thread and any probe. The lock has to refuse a second owner instead of letting
## two simulations interleave over the same movement fields.
func _run_lock_case() -> Array[String]:
	var failures: Array[String] = []
	var nav := GRID.new() as AutopilotGrid
	if not nav.build_from_rows(LOCK_ROWS):
		return ["lock fixture failed to build"]
	var sim := MOTION.new() as AutopilotMotion
	sim.configure(nav, PROFILE.new(), DASH_DEFINITION.new(), 120.0)
	var planner := PLANNER.new() as AutopilotPlanner
	planner.configure(nav, sim)
	var start := {
		"position": nav.cell_to_world(Vector2i(2, 6)),
		"velocity": Vector2.ZERO,
		"mode": 0,
		"dash_charge": true,
		"stamina": 110.0,
	}
	var walk := {"name": &"walk", "axis": 1.0, "max_ticks": 20}
	if sim.simulate(start, walk) == null:
		failures.append("the simulator refused an idle call")
	if nav.lock.is_locked():
		failures.append("the lock stayed held after a simulate call")
	if not nav.lock.try_acquire(&"probe"):
		failures.append("the lock refused its first owner")
	if sim.simulate(start, walk) != null:
		failures.append("the simulator ran while another owner held the lock")
	if not planner.plan(start, nav.cell_to_world(Vector2i(9, 6))).is_empty():
		failures.append("the planner planned while another owner held the lock")
	nav.lock.release(&"probe")
	if nav.lock.is_locked():
		failures.append("the lock stayed held after release")
	if sim.simulate(start, walk) == null:
		failures.append("the simulator stayed locked after release")
	if planner.plan(start, nav.cell_to_world(Vector2i(9, 6))).is_empty():
		failures.append("the planner stayed locked after release")
	return failures


## The tile one-way platform the shipped tileset uses: solid to stand on and to
## land on, passable when rising from below.
func _run_one_way_case() -> Array[String]:
	var failures: Array[String] = []
	var nav := GRID.new() as AutopilotGrid
	if not nav.build_from_rows(ONE_WAY_ROWS):
		return ["one-way fixture failed to build"]
	var platform := Vector2i(17, 6)
	if not nav.cell_is_free(platform):
		failures.append("a one-way platform cell is treated as solid")
	if not nav.cell_is_standable(platform):
		failures.append("a one-way platform is not a foothold")
	nav.move_box(Vector2(17 * 8.0, 36.0), Vector2(0.0, 16.0))
	if not nav.last_move_hit_y:
		failures.append("a falling body passed through a one-way platform")
	elif absf(nav.last_move_position.y - 48.0) > 1.0:
		failures.append(
			"a falling body stopped %.1f px above a one-way platform"
			% absf(nav.last_move_position.y - 48.0)
		)
	nav.move_box(Vector2(17 * 8.0, 64.0), Vector2(0.0, -14.0))
	if nav.last_move_hit_y:
		failures.append("a body rising from below was blocked by a one-way platform")
	elif nav.last_move_position.y > 50.5:
		failures.append(
			"a rising body did not pass into the platform (stopped at %.1f)" % nav.last_move_position.y
		)
	return failures


func _run_case(test: Node) -> Array[String]:
	add_child(test)
	var result: Array = test.call("run")
	test.queue_free()
	var failures: Array[String] = []
	failures.assign(result)
	return failures


class GridCase extends Node:
	const GRID := preload("res://addons/platformer_kit/character/autopilot/autopilot_grid.gd")


	func run() -> Array[String]:
		var failures: Array[String] = []
		var nav := GRID.new() as AutopilotGrid
		if not nav.build_from_rows(OPEN_ROWS):
			return ["ASCII grid failed to build"]
		if nav.cell_is_standable(Vector2i(4, 6)):
			failures.append("an unsupported cell is reported as a foothold")
		if nav.cell_is_standable(Vector2i(4, 8)):
			failures.append("a cell inside the floor is reported as a foothold")
		if not nav.cell_is_standable(Vector2i(4, 7)):
			failures.append("the floor row is not a foothold")
		if not nav.cell_is_free(Vector2i(4, 4)):
			failures.append("open air is not free")
		if nav.cell_is_free(Vector2i(4, 8)):
			failures.append("a cell inside the floor is walkable")
		if nav.cell_is_ladder(Vector2i(4, 4)):
			failures.append("a plain cell is reported as ladder")
		if nav.world_to_cell(Vector2(72.0, 64.0)) != Vector2i(9, 8):
			failures.append("cell conversion is wrong")
		var snapped := nav.find_standable_cell(Vector2(70.0, 70.0), 3)
		if snapped == AutopilotGrid.INVALID_CELL:
			failures.append("no foothold found near the floor")
		elif not nav.cell_is_standable(snapped):
			failures.append("the snap result is not a foothold")
		var ladder := GRID.new() as AutopilotGrid
		ladder.build_from_rows(LADDER_ROWS)
		if not ladder.cell_is_standable(Vector2i(20, 12)):
			failures.append("the floor inside a ladder footprint is not standable")
		if not ladder.cell_is_ladder(Vector2i(20, 10)):
			failures.append("a ladder cell was not marked")
		if ladder.cell_is_standable(Vector2i(20, 10)):
			failures.append("a mid-ladder cell was marked as a foothold")
		if not ladder.cell_is_ladder(Vector2i(20, 4)):
			failures.append("the ladder top at the platform row is missing")
		return failures


class MotionCase extends Node:
	const GRID := preload("res://addons/platformer_kit/character/autopilot/autopilot_grid.gd")
	const MOTION := preload("res://addons/platformer_kit/character/autopilot/autopilot_motion.gd")
	const PROFILE := preload("res://addons/platformer_kit/character/resources/movement_profile.gd")
	const DASH_DEFINITION := preload(
		"res://addons/platformer_kit/abilities/dash/dash_ability_definition.gd"
	)


	func run() -> Array[String]:
		var failures: Array[String] = []
		var nav := GRID.new() as AutopilotGrid
		nav.build_from_rows(OPEN_ROWS)
		var sim := MOTION.new() as AutopilotMotion
		sim.configure(nav, PROFILE.new(), DASH_DEFINITION.new(), 120.0)
		var start_position := nav.cell_to_world(Vector2i(4, 7))
		var start := {
			"position": start_position,
			"velocity": Vector2.ZERO,
			"mode": 0,
			"dash_charge": true,
			"stamina": 110.0,
		}
		var full_jump := sim.simulate(start, {"name": &"jump", "axis": 1.0, "hold_ticks": 26})
		if full_jump == null:
			failures.append("a forward jump produced no leg")
		else:
			if full_jump.end_mode != 0:
				failures.append("a jump on flat ground did not land")
			if full_jump.end_cell.x <= 5:
				failures.append("a forward jump did not travel forward (%s)" % [full_jump.end_cell])
			if full_jump.frames < 20 or full_jump.frames > 220:
				failures.append("a jump lasted an implausible time: %d" % full_jump.frames)
			if not full_jump.get_intent(0).jump_pressed:
				failures.append("the jump leg does not press jump on its first tick")
		var full_peak := peak_of(sim, start, 26)
		var tap_peak := peak_of(sim, start, 3)
		if full_peak > -16.0:
			failures.append("a held jump barely rose (%.1f)" % full_peak)
		if tap_peak <= full_peak + 6.0:
			failures.append("a tap jump is not shorter than a held jump (%.1f vs %.1f)" % [tap_peak, full_peak])
		var dash_up := sim.simulate(
			start,
			{"name": &"dash", "axis": 1.0, "dash_dir": Vector2(0.7071, -0.7071)}
		)
		if dash_up == null:
			failures.append("an up-right dash produced no leg")
		else:
			var dash_peak := 0.0
			for sample: Vector2 in dash_up.samples:
				dash_peak = minf(dash_peak, sample.y - start_position.y)
			if dash_peak > -16.0:
				failures.append("an up-right dash did not climb (%.1f)" % dash_peak)
		var dash_right := sim.simulate(
			start,
			{"name": &"dash", "axis": 1.0, "dash_dir": Vector2(1.0, 0.0)}
		)
		if dash_right == null:
			failures.append("a ground dash produced no leg")
		elif dash_right.end_position.x < start_position.x + 32.0:
			failures.append("a ground dash is shorter than one dash length")
		var super_jump := sim.simulate(
			start,
			{"name": &"dash_jump", "axis": 1.0, "dash_dir": Vector2(1.0, 0.0)}
		)
		if super_jump == null:
			failures.append("dash then jump produced no leg")
		elif dash_right != null and super_jump.end_position.x <= dash_right.end_position.x:
			failures.append("dash-jump does not extend a dash")
		var jump_dash := sim.simulate(
			start,
			{
				"name": &"jump_dash",
				"axis": 1.0,
				"dash_dir": Vector2(0.7071, -0.7071),
				"delay_ticks": 18,
			}
		)
		if jump_dash == null:
			failures.append("jump then dash produced no leg")
		else:
			var combo_peak := 0.0
			for sample: Vector2 in jump_dash.samples:
				combo_peak = minf(combo_peak, sample.y - start_position.y)
			if combo_peak > full_peak:
				failures.append("jump then dash does not climb higher than a jump")
		failures.append_array(_check_ladder())
		failures.append_array(_check_wall())
		return failures


	func peak_of(sim: AutopilotMotion, start: Dictionary, hold_ticks: int) -> float:
		# Move while jumping so the leg is not discarded as a same-cell no-op.
		var leg := sim.simulate(start, {"name": &"jump", "axis": 1.0, "hold_ticks": hold_ticks})
		if leg == null:
			return 0.0
		var peak := 0.0
		for sample: Vector2 in leg.samples:
			peak = minf(peak, sample.y - Vector2(start.position).y)
		return peak


	func _check_ladder() -> Array[String]:
		var failures: Array[String] = []
		var nav := GRID.new() as AutopilotGrid
		nav.build_from_rows(LADDER_ROWS)
		var sim := MOTION.new() as AutopilotMotion
		sim.configure(nav, PROFILE.new(), DASH_DEFINITION.new(), 120.0)
		var state := {
			"position": nav.cell_to_world(Vector2i(20, 11)),
			"velocity": Vector2.ZERO,
			"mode": LEG.MODE_LADDER,
			"dash_charge": true,
			"stamina": 110.0,
		}
		var climb := sim.simulate(state, {"name": &"ladder", "vertical": -1.0})
		if climb == null:
			failures.append("climbing a ladder produced no leg")
		else:
			if climb.end_position.y >= Vector2(state.position).y:
				failures.append("a ladder climb did not gain height")
			if climb.end_mode != LEG.MODE_LADDER:
				failures.append("a ladder climb did not stay on the ladder")
		var step_off := sim.simulate(state, {"name": &"ladder", "axis": 1.0, "vertical": 0.0, "ticks": 16})
		if step_off == null or step_off.end_position.x <= Vector2(state.position).x:
			failures.append("stepping sideways on a ladder did not move")
		return failures


	func _check_wall() -> Array[String]:
		var failures: Array[String] = []
		var nav := GRID.new() as AutopilotGrid
		nav.build_from_rows(WALL_ROWS)
		var sim := MOTION.new() as AutopilotMotion
		sim.configure(nav, PROFILE.new(), DASH_DEFINITION.new(), 120.0)
		var wall_state := {
			"position": Vector2(109.0, 56.0),
			"velocity": Vector2.ZERO,
			"mode": LEG.MODE_WALL_RIGHT,
			"dash_charge": true,
			"stamina": 110.0,
		}
		if not nav.has_wall(Vector2(109.0, 56.0), 1):
			failures.append("the fixture wall is not detected next to the character")
		var up := sim.simulate(wall_state, {"name": &"wall_step", "vertical": -1.0, "ticks": 22})
		if up == null:
			failures.append("climbing a wall produced no leg")
		else:
			if up.end_position.y >= 56.0:
				failures.append("a wall climb did not gain height")
			if up.end_mode != LEG.MODE_WALL_RIGHT:
				failures.append("a wall climb did not stay on the wall")
			if up.stamina_after >= 110.0:
				failures.append("a wall climb did not spend stamina")
		var jump := sim.simulate(wall_state, {"name": &"wall_jump", "max_ticks": 200})
		if jump == null:
			failures.append("a wall jump produced no leg")
		else:
			var jump_peak := 9999.0
			for sample: Vector2 in jump.samples:
				jump_peak = minf(jump_peak, sample.y)
			if jump_peak > 56.0 - 12.0:
				failures.append("a wall jump did not gain height (peak %.1f)" % jump_peak)
			if jump.get_intent(0).axis > 0.0:
				failures.append("a wall jump does not push away from the wall")
		var climb_jump := sim.simulate(wall_state, {"name": &"wall_climb_jump", "max_ticks": 200})
		if climb_jump == null:
			failures.append("a wall climb jump produced no leg")
		else:
			var climb_peak := 9999.0
			for sample: Vector2 in climb_jump.samples:
				climb_peak = minf(climb_peak, sample.y)
			if climb_peak > 56.0 - 18.0:
				failures.append("a wall climb jump did not clear the wall (peak %.1f)" % climb_peak)
		return failures


class PlannerCase extends Node:
	const GRID := preload("res://addons/platformer_kit/character/autopilot/autopilot_grid.gd")
	const MOTION := preload("res://addons/platformer_kit/character/autopilot/autopilot_motion.gd")
	const PLANNER := preload("res://addons/platformer_kit/character/autopilot/autopilot_planner.gd")
	const PROFILE := preload("res://addons/platformer_kit/character/resources/movement_profile.gd")
	const DASH_DEFINITION := preload(
		"res://addons/platformer_kit/abilities/dash/dash_ability_definition.gd"
	)


	func run() -> Array[String]:
		var failures: Array[String] = []
		failures.append_array(_check_gap())
		failures.append_array(_check_ledge())
		failures.append_array(_check_ladder())
		failures.append_array(_check_wall())
		failures.append_array(_check_ability_gate())
		failures.append_array(_check_sealed())
		return failures


	func _planner_for(rows: Array[String]) -> Dictionary:
		var nav := GRID.new() as AutopilotGrid
		nav.build_from_rows(rows)
		var sim := MOTION.new() as AutopilotMotion
		sim.configure(nav, PROFILE.new(), DASH_DEFINITION.new(), 120.0)
		var planner := PLANNER.new() as AutopilotPlanner
		planner.configure(nav, sim)
		return {"grid": nav, "planner": planner}


	func _route_to(
		setup: Dictionary,
		start_cell: Vector2i,
		goal_cell: Vector2i
	) -> AutopilotRoute:
		var nav: AutopilotGrid = setup.grid
		var planner: AutopilotPlanner = setup.planner
		return planner.plan(
			{
				"position": nav.cell_to_world(start_cell),
				"velocity": Vector2.ZERO,
				"mode": 0,
				"dash_charge": true,
				"stamina": 110.0,
			},
			nav.cell_to_world(goal_cell)
		)


	func _check_gap() -> Array[String]:
		var failures: Array[String] = []
		var setup := _planner_for(GAP_ROWS)
		var route := _route_to(setup, Vector2i(2, 6), Vector2i(12, 6))
		if route.is_empty():
			failures.append("a jumpable gap produced no route")
		else:
			var labels := route.get_action_labels()
			if not (labels.has("跳") or labels.has("跳冲") or labels.has("冲刺") or labels.has("冲刺跳")):
				failures.append("crossing a gap used no jump: %s" % [route.describe()])
			if route.get_frames() > 500:
				failures.append("the gap route is implausibly long: %d" % route.get_frames())
			failures.append_array(_check_continuity(route, "gap"))
		return failures


	## Consecutive legs must pick up exactly where the previous leg ended,
	## otherwise the driver replays a disconnected script.
	func _check_continuity(route: AutopilotRoute, label: String) -> Array[String]:
		var failures: Array[String] = []
		for index: int in range(1, route.get_leg_count()):
			var previous: AutopilotLeg = route.legs[index - 1]
			var current: AutopilotLeg = route.legs[index]
			var gap := previous.end_position.distance_to(current.start_position)
			if gap > 2.0:
				failures.append(
					"%s route leg %d (%s) starts %.1f px away from leg %d's end (%s)"
					% [label, index, current.action_code(), gap, index - 1, previous.action_code()]
				)
		return failures


	func _check_ledge() -> Array[String]:
		var failures: Array[String] = []
		var setup := _planner_for(LEDGE_ROWS)
		var route := _route_to(setup, Vector2i(2, 7), Vector2i(27, 3))
		if route.is_empty():
			failures.append("a raised ledge produced no route")
		return failures


	func _check_ladder() -> Array[String]:
		var failures: Array[String] = []
		var setup := _planner_for(LADDER_ROWS)
		var route := _route_to(setup, Vector2i(2, 12), Vector2i(23, 4))
		if route.is_empty():
			failures.append("a ladder to a platform produced no route")
		else:
			if not route.get_action_labels().has("爬梯"):
				failures.append("the ladder route did not climb: %s" % [route.describe()])
			failures.append_array(_check_continuity(route, "ladder"))
		return failures


	func _check_wall() -> Array[String]:
		var failures: Array[String] = []
		var setup := _planner_for(WALL_ROWS)
		var route := _route_to(setup, Vector2i(2, 15), Vector2i(18, 3))
		if route.is_empty():
			failures.append("a climbable wall produced no route")
		else:
			var labels := route.get_action_labels()
			if not (labels.has("攀墙") or labels.has("登墙跳")):
				failures.append("the wall route does not climb: %s" % [route.describe()])
			failures.append_array(_check_continuity(route, "wall"))
		return failures


	## The planner must respect the abilities the character actually owns: a route
	## for a character without the Dash or Climb unlock may not contain them.
	func _check_ability_gate() -> Array[String]:
		var failures: Array[String] = []
		var setup := _planner_for(WIDE_GAP_ROWS)
		var motion: AutopilotMotion = setup.planner.motion
		var with_dash := _route_to(setup, Vector2i(2, 6), Vector2i(22, 6))
		if with_dash.is_empty():
			failures.append("a dash-jumpable gap produced no route with the dash enabled")
		else:
			var labels := with_dash.get_action_labels()
			if not (
				labels.has("冲刺") or labels.has("冲刺跳") or labels.has("跳冲")
			):
				failures.append("the wide gap route did not use a dash: %s" % [with_dash.describe()])
		motion.dash_enabled = false
		motion.climb_enabled = false
		var locked := _route_to(setup, Vector2i(2, 6), Vector2i(22, 6))
		for leg: AutopilotLeg in locked.legs:
			if (
				leg.action == &"dash"
				or leg.action == &"dash_jump"
				or leg.action == &"jump_dash"
				or leg.action == &"wall_step"
				or leg.action == &"wall_jump"
				or leg.action == &"wall_climb_jump"
			):
				failures.append(
					"a locked ability was planned: %s in %s" % [leg.action_code(), locked.describe()]
				)
				break
		motion.dash_enabled = true
		motion.climb_enabled = true
		return failures


	func _check_sealed() -> Array[String]:
		var failures: Array[String] = []
		var rows: Array[String] = []
		for row: String in SEALED_ROWS:
			rows.append(row.replace("-", "#"))
		var setup := _planner_for(rows)
		var route := _route_to(setup, Vector2i(2, 15), Vector2i(15, 9))
		if not route.is_empty():
			failures.append("a sealed pocket produced a route: %s" % [route.describe()])
		return failures


class DriverCase extends Node:
	const LEG := preload("res://addons/platformer_kit/character/autopilot/autopilot_leg.gd")
	const ROUTE := preload("res://addons/platformer_kit/character/autopilot/autopilot_route.gd")
	const DRIVER := preload("res://addons/platformer_kit/character/autopilot/autopilot_driver.gd")

	var finished := false
	var deviations := 0


	func run() -> Array[String]:
		var failures: Array[String] = []
		var actor := Node2D.new()
		add_child(actor)
		var route := ROUTE.new() as AutopilotRoute
		var leg := LEG.new()
		leg.action = &"jump"
		var position := Vector2.ZERO
		for tick: int in range(12):
			position += Vector2(2.0, -1.0)
			leg.append_tick(1.0, 0.0, tick == 0, tick < 6, Vector2.ZERO, position)
		leg.end_cell = Vector2i(3, 0)
		leg.end_mode = LEG.MODE_GROUND
		route.append_leg(leg)
		var driver := DRIVER.new() as AutopilotDriver
		driver.configure(actor, null)
		driver.set_route(route)
		driver.route_finished.connect(func(_reached: bool) -> void: finished = true)
		driver.route_deviation.connect(func(_at: Vector2) -> void: deviations += 1)
		if not driver.is_active():
			failures.append("the driver did not activate on a non-empty route")
		for tick: int in range(12):
			actor.global_position = leg.get_sample(maxi(tick - 1, 0))
			var intent = driver.get_intent()
			if tick == 0 and (not intent.jump_pressed or not intent.jump_held):
				failures.append("the driver lost the jump press on the first tick")
			if tick == 1 and intent.jump_pressed:
				failures.append("the driver repeated the jump press")
			if tick < 6 and not intent.jump_held:
				failures.append("the driver released a planned jump hold at tick %d" % tick)
			# One-sided relaxation: the hold may run a few ticks past the plan.
			if tick >= 10 and intent.jump_held:
				failures.append("the driver held jump %d ticks past the plan" % (tick - 5))
		if not finished:
			failures.append("the driver did not report route completion")
		if deviations != 0:
			failures.append("the driver reported drift on a perfect replay")
		var drifting := DRIVER.new() as AutopilotDriver
		drifting.configure(actor, null)
		drifting.set_route(route)
		drifting.route_deviation.connect(func(_at: Vector2) -> void: deviations += 1)
		actor.global_position = Vector2(120.0, 120.0)
		drifting.get_intent()
		drifting.get_intent()
		if deviations == 0:
			failures.append("the driver did not report a large drift")
		if drifting.is_active():
			failures.append("the driver kept playing after a drift")
		actor.queue_free()
		return failures
