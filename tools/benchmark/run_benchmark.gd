extends SceneTree
## Solver benchmark: plan every benchmark room and grade the result.
##
##   godot --headless --path . -s res://tools/benchmark/run_benchmark.gd
##   godot --headless --path . -s res://tools/benchmark/run_benchmark.gd -- --bias=0
##   godot --headless --path . -s res://tools/benchmark/run_benchmark.gd -- --verbose
##
## A room passes when the planner finds a route and the route's simulated length
## fits the room's frame budget. It also reports the mean clearance of the route
## (the stability score the cost relaxation prefers) so the bias can be compared:
## the biased run must stay feasible and should not score lower.

const GRID = preload("res://addons/platformer_kit/character/autopilot/autopilot_grid.gd")
const MOTION = preload("res://addons/platformer_kit/character/autopilot/autopilot_motion.gd")
const PLANNER = preload("res://addons/platformer_kit/character/autopilot/autopilot_planner.gd")
const PROFILE = preload("res://addons/platformer_kit/character/resources/movement_profile.gd")
const DASH = preload("res://addons/platformer_kit/abilities/dash/dash_ability_definition.gd")
const ROOMS = preload("res://tools/benchmark/benchmark_rooms.gd")

const TICK_RATE := 120.0

var _verbose := false
var _bias := -1.0
var _effective_bias := 0.0


func _init() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--bias="):
			_bias = float(argument.trim_prefix("--bias="))
		elif argument == "--verbose":
			_verbose = true
	var failures := 0
	var total_frames := 0
	var total_ms := 0
	var total_stability := 0.0
	var lines: Array[String] = []
	lines.append("%-16s %-5s %-5s %-4s %-11s %-5s %-6s %s" % [
		"room", "dash", "climb", "ok", "frames/limit", "legs", "ms", "clear",
	])
	for spec: Dictionary in ROOMS.specs():
		var outcome := _run_room(spec)
		total_frames += int(outcome.get("frames", 0))
		total_ms += int(outcome.get("ms", 0))
		total_stability += float(outcome.get("stability", 0.0))
		if not bool(outcome.get("ok", false)):
			failures += 1
		lines.append("%-16s %-5s %-5s %-4s %-11s %-5d %-6d %.2f" % [
			String(spec.id),
			"yes" if bool(spec.dash) else "no",
			"yes" if bool(spec.climb) else "no",
			"PASS" if bool(outcome.get("ok", false)) else "FAIL",
			"%d/%d" % [int(outcome.get("frames", 0)), int(outcome.get("limit", 0))],
			int(outcome.get("legs", 0)),
			int(outcome.get("ms", 0)),
			float(outcome.get("stability", 0.0)),
		])
		if _verbose and not String(outcome.get("detail", "")).is_empty():
			lines.append("    " + String(outcome.detail))
	lines.append("")
	lines.append("%d rooms, %d failed, %d frames total, %d ms planning, mean clearance %.2f (bias %.1f)" % [
		ROOMS.specs().size(), failures, total_frames, total_ms,
		total_stability / maxf(float(ROOMS.specs().size()), 1.0), _effective_bias,
	])
	for line: String in lines:
		print(line)
	quit(1 if failures > 0 else 0)


func _run_room(spec: Dictionary) -> Dictionary:
	var nav := GRID.new() as AutopilotGrid
	if not nav.build_from_rows(ROOMS.render(spec)):
		return {"ok": false, "detail": "%s: fixture failed to build" % spec.id}
	var sim := MOTION.new() as AutopilotMotion
	sim.configure(nav, PROFILE.new(), DASH.new(), TICK_RATE)
	sim.dash_enabled = bool(spec.dash)
	sim.climb_enabled = bool(spec.climb)
	var planner := PLANNER.new() as AutopilotPlanner
	planner.configure(nav, sim)
	if _bias >= 0.0:
		planner.stability_bias = _bias
	_effective_bias = planner.stability_bias
	var start_cell := _snap(nav, spec.start)
	var goal_cell := _snap(nav, spec.goal)
	if start_cell == AutopilotGrid.INVALID_CELL or goal_cell == AutopilotGrid.INVALID_CELL:
		return {"ok": false, "detail": "%s: waypoint is not on a foothold" % spec.id}
	var started: int = Time.get_ticks_msec()
	var route = planner.plan(_start_state(nav, start_cell), nav.cell_to_world(goal_cell))
	var elapsed: int = Time.get_ticks_msec() - started
	var limit := int(float(spec.seconds) * TICK_RATE)
	var legs: Array[String] = []
	for leg: AutopilotLeg in route.legs:
		legs.append("%s%s" % [String(leg.action_code()), str(leg.end_cell)])
	return {
		"ok": not route.is_empty() and route.get_frames() <= limit,
		"frames": route.get_frames(),
		"limit": limit,
		"legs": route.get_leg_count(),
		"ms": elapsed,
		"stability": planner.route_stability(route),
		"detail": "%s -> %s: %s" % [str(start_cell), str(goal_cell), " > ".join(legs)],
	}


func _snap(nav: AutopilotGrid, cell: Vector2i) -> Vector2i:
	if nav.cell_is_standable(cell):
		return cell
	return nav.find_standable_cell(nav.cell_to_world(cell), 5)


func _start_state(nav: AutopilotGrid, cell: Vector2i) -> Dictionary:
	return {
		"position": nav.cell_to_world(cell),
		"velocity": Vector2.ZERO,
		"mode": 0,
		"dash_charge": true,
		"stamina": 110.0,
	}
