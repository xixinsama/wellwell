extends Node2D
class_name PlatformerAutoRouteTool

## Debug tool: pick a start and a goal inside the current room, plan a route with
## the autopilot solver and let the character run it with real input.
##
## F4 opens the tool. Arrows or WASD move an 8 px cursor, Space pins the start,
## X pins the goal, Enter plans and runs, Backspace clears, F4 closes. The
## overlay text is ASCII because the engine's default font has no CJK glyphs.

const GRID := preload("res://addons/platformer_kit/character/autopilot/autopilot_grid.gd")
const MOTION := preload("res://addons/platformer_kit/character/autopilot/autopilot_motion.gd")
const PLANNER := preload("res://addons/platformer_kit/character/autopilot/autopilot_planner.gd")
const DRIVER := preload("res://addons/platformer_kit/character/autopilot/autopilot_driver.gd")
const ROUTE := preload("res://addons/platformer_kit/character/autopilot/autopilot_route.gd")
const LEG := preload("res://addons/platformer_kit/character/autopilot/autopilot_leg.gd")
const CHARACTER_INTENT := preload(
	"res://addons/platformer_kit/character/input/character_intent.gd"
)

enum Mode { OFF, PICK, RUNNING }

## Swallows player input while the tool owns the keyboard.
class NoopInput extends RefCounted:
	func get_intent() -> CharacterIntent:
		return CharacterIntent.new()

const HINT_COLOR := Color(0.62, 0.78, 0.8, 0.95)
const START_COLOR := Color(0.42, 0.95, 0.5, 1.0)
const GOAL_COLOR := Color(0.98, 0.4, 0.82, 1.0)
const CURSOR_COLOR := Color(0.98, 0.87, 0.33, 1.0)
const BAD_COLOR := Color(0.98, 0.45, 0.38, 1.0)

@export var player_path := NodePath("../Player")
@export var world_root_path := NodePath("..")
@export var toggle_keycode: int = KEY_F4
@export var start_enabled := false

var _mode := Mode.OFF
var _player: Node2D
var _world_root: Node
var _base_source: RefCounted
var _neutral := NoopInput.new()
var _grid: AutopilotGrid
var _motion: AutopilotMotion
var _planner: AutopilotPlanner
var _driver: AutopilotDriver
var _route: AutopilotRoute
var _room_id := ""
var _cursor_cell := Vector2i.ZERO
var _start_cell := AutopilotGrid.INVALID_CELL
var _goal_cell := AutopilotGrid.INVALID_CELL
var _status_line := ""
var _status_color := HINT_COLOR
var _plan_requested := false
var _planned_seconds := 0.0
## Async plan bookkeeping: the search runs on a worker thread.
var _planning := false
var _plan_task_id := -1
var _plan_thread_route: AutopilotRoute
var _plan_thread_done := false
var _plan_start_state := {}
var _plan_started_ms := 0
var _course: Array[Vector2] = []
var _course_index := 0
var _plan_is_initial := false
var _plan_attempts := 0
var _last_reported_leg := -1
var _grid_footholds := 0
var _grid_built_ms := 0
## Watchdog: a run that stops making progress replans once, then gives up.
var _progress_position := Vector2.ZERO
var _progress_ms := 0
var _stuck_count := 0
## How many times a route ran out short of the goal; bounded so it gives up.
var _finish_attempts := 0
## Set when a drift needs a feet-on-the-ground start before replanning.
var _replan_pending := false
## Last drift report, kept for playtests and the status line.
var _last_deviation := {}
## Recent drift reports: which leg, how far off, and the per-leg entry error.
var _deviation_history: Array[Dictionary] = []
## Edge detection for the raw keys, which are polled so the tool works inside
## the gameplay SubViewport (it does not receive unhandled key events).
var _key_was_down := {}
## Scan effect: the raster is built in slices while a sweep crosses the room.
var _scan_active := false
var _scan_progress := 0.0
var _scan_fade := 0.0
var _scan_done_ms := 0
var _scan_attempts := 0
var _scan_retry_ms := 0
## Pins requested before the raster finished.
var _pending_start := Vector2.INF
var _pending_goal := Vector2.INF
const SCAN_FINE_ROWS := 5
const SCAN_NAV_ROWS := 4
const SCAN_FADE_MS := 550.0


func _ready() -> void:
	_player = get_node_or_null(player_path) as Node2D
	_world_root = get_node_or_null(world_root_path)
	# Keyboard input is polled in _process: nodes inside the gameplay
	# SubViewport do not get _unhandled_input for keys.
	set_process(true)
	set_physics_process(false)
	if start_enabled:
		_open()


func _exit_tree() -> void:
	# Never leave a worker writing into a freed tool.
	if _plan_task_id >= 0:
		WorkerThreadPool.wait_for_task_completion(_plan_task_id)
		_plan_task_id = -1


func _physics_process(_delta: float) -> void:
	if _mode == Mode.OFF:
		return
	if _planning or _scan_active:
		return
	if _plan_requested:
		_plan_requested = false
		_request_plan(true)
	if _replan_pending and _driver == null:
		var settled: bool = _player != null and _is_settled()
		if settled:
			_replan_pending = false
			_request_plan(false)
	_sync_status()


## Standing (or hanging) on the goal, close enough that the planner agrees.
func _standing_at_goal() -> bool:
	if _player == null or _grid == null or _goal_cell == AutopilotGrid.INVALID_CELL:
		return false
	var standing := false
	if _player.has_method("get_debug_state"):
		var debug: Dictionary = _player.call("get_debug_state")
		var motion_state := int(debug.get("state", 0))
		standing = (
			bool(debug.get("on_floor", false))
			or motion_state == 2
			or motion_state == 3
			or (_player.has_method("is_on_ladder") and bool(_player.call("is_on_ladder")))
		)
	elif _player.has_method("is_on_floor"):
		standing = bool(_player.call("is_on_floor"))
	if not standing:
		return false
	return (
		_player.global_position.distance_to(_grid.cell_to_world(_goal_cell))
		<= AutopilotPlanner.GOAL_POSITION_TOLERANCE
	)
func _is_settled() -> bool:
	if _player == null:
		return false
	if _player.is_on_floor():
		return true
	if _player.has_method("is_on_ladder") and bool(_player.call("is_on_ladder")):
		return true
	if not _player.has_method("get_debug_state"):
		return false
	var debug: Dictionary = _player.call("get_debug_state")
	var motion_state := int(debug.get("state", 0))
	# 1 dash, 4 swim, 6 hurt: wait for a state the planner can start from.
	if motion_state == 1 or motion_state == 4 or motion_state == 6:
		return false
	return motion_state == 2 or motion_state == 3


func _process(_delta: float) -> void:
	_poll_keys()
	_poll_plan()
	if _mode == Mode.OFF:
		return
	_check_room_change()
	if _mode == Mode.OFF:
		return
	if _scan_active:
		_drive_scan()
		queue_redraw()
		return
	if _scan_retry_ms > 0 and Time.get_ticks_msec() >= _scan_retry_ms:
		_scan_retry_ms = 0
		_begin_scan()
		queue_redraw()
		return
	if _scan_fade > 0.0:
		_scan_fade = maxf(
			0.0,
			1.0 - float(Time.get_ticks_msec() - _scan_done_ms) / SCAN_FADE_MS
		)
	queue_redraw()


## Advance the raster by a slice and keep the status line honest about it.
func _drive_scan() -> void:
	if _grid == null or not _grid.is_building():
		_scan_active = false
		return
	var done := _grid.build_step(SCAN_FINE_ROWS, SCAN_NAV_ROWS)
	_scan_progress = _grid.build_progress()
	if done:
		_finish_scan()
		return
	_status_line = "SCANNING  %d%%" % roundi(_scan_progress * 100.0)


## A streamed room change closes the tool: the raster is only built when the
## player deliberately opens it again, never on entering or leaving a room.
func _check_room_change() -> void:
	var room_id := _current_room_id()
	if room_id == _room_id and not room_id.is_empty():
		return
	if room_id.is_empty():
		return
	_close()
	_grid = null
	_motion = null
	_planner = null
	_grid_footholds = 0
	_route = null
	_deviation_history.clear()
	_last_deviation = {}
	_room_id = room_id
	_status_line = ""
	queue_redraw()


func _poll_keys() -> void:
	if _was_pressed(toggle_keycode):
		if _mode == Mode.OFF:
			_open()
		else:
			_close()
		return
	if _mode == Mode.OFF:
		return
	var fast := Input.is_key_pressed(KEY_SHIFT)
	if _was_pressed(KEY_LEFT) or _was_pressed(KEY_A):
		_move_cursor(Vector2i(-1, 0), fast)
	if _was_pressed(KEY_RIGHT) or _was_pressed(KEY_D):
		_move_cursor(Vector2i(1, 0), fast)
	if _was_pressed(KEY_UP) or _was_pressed(KEY_W):
		_move_cursor(Vector2i(0, -1), fast)
	if _was_pressed(KEY_DOWN) or _was_pressed(KEY_S):
		_move_cursor(Vector2i(0, 1), fast)
	if _was_pressed(KEY_SPACE):
		_set_start_here()
	if _was_pressed(KEY_X):
		_set_goal_here()
	if _was_pressed(KEY_ENTER) or _was_pressed(KEY_KP_ENTER) or _was_pressed(KEY_Z):
		_status_line = "PLANNING..."
		_status_color = HINT_COLOR
		queue_redraw()
		_plan_requested = true
	if _was_pressed(KEY_BACKSPACE):
		_clear_points()
	if _was_pressed(KEY_ESCAPE):
		_close()


func _was_pressed(keycode: int) -> bool:
	var down := Input.is_key_pressed(keycode)
	var was_down: bool = bool(_key_was_down.get(keycode, false))
	_key_was_down[keycode] = down
	return down and not was_down


# --- public surface (also used by playtests and other tools) -----------------

func open_tool() -> void:
	_open()


func close_tool() -> void:
	_close()


func is_open() -> bool:
	return _mode != Mode.OFF


## Pins can be set before the scan finishes: the request is applied when the
## raster is ready, so a scripted playtest does not have to time the frames.
func set_start(world_position: Vector2) -> bool:
	if _grid == null or _scan_active or not _grid.is_built():
		_pending_start = world_position
		return true
	var cell := _grid.find_goal_cell(world_position, 8)
	if cell == AutopilotGrid.INVALID_CELL:
		return false
	_start_cell = cell
	_status_line = "START PINNED"
	queue_redraw()
	return true


func set_goal(world_position: Vector2) -> bool:
	if _grid == null or _scan_active or not _grid.is_built():
		_pending_goal = world_position
		return true
	var cell := _grid.find_goal_cell(world_position, 8)
	if cell == AutopilotGrid.INVALID_CELL:
		return false
	_goal_cell = cell
	_status_line = "GOAL PINNED"
	queue_redraw()
	return true


## Ordered waypoint course authored with NumberPickup nodes that carry a
## `waypoint_index` (0 = first, then ascending). Empty when the room has none.
func get_waypoint_course() -> Array[Vector2]:
	var course: Array[Vector2] = []
	for node: Node in get_tree().get_nodes_in_group(&"solver_waypoint"):
		var node_2d := node as Node2D
		if node_2d == null:
			continue
		var index := int(node_2d.get("waypoint_index")) if "waypoint_index" in node_2d else -1
		if index < 0:
			continue
		while course.size() <= index:
			course.append(Vector2.INF)
		course[index] = node_2d.global_position
	return course


## Plan through the room's waypoint course in order, then to the picked goal.
func start_waypoint_course() -> bool:
	var course := get_waypoint_course()
	if course.is_empty():
		_status_line = "NO WAYPOINTS IN THIS ROOM"
		_status_color = BAD_COLOR
		return false
	_course = course
	_course_index = 0
	_goal_cell = _grid.find_goal_cell(course[0], 10) if _grid != null else AutopilotGrid.INVALID_CELL
	_status_line = "WAYPOINT 1/%d" % course.size()
	_plan_requested = true
	return true



func plan_and_run() -> bool:
	if _scan_active or _grid == null or not _grid.is_built():
		_plan_requested = true
		return true
	return _request_plan(true)


func get_status_line() -> String:
	return _status_line


func get_last_deviation() -> Dictionary:
	return _last_deviation


func get_route() -> AutopilotRoute:
	return _route


func get_progress() -> Dictionary:
	if _driver == null:
		return {"active": false, "leg": 0, "leg_count": 0, "action": ""}
	return _driver.get_progress()


## Whether the shared raster and simulator are safe to touch right now. The tool
## plans on a worker thread and scans in slices, so an outside probe has to ask
## before it simulates: two owners on the same movement fields corrupt each other.
func get_lock_state() -> Dictionary:
	var locked_by := ""
	if _grid != null:
		locked_by = String(_grid.lock.holder())
	return {
		"open": _mode != Mode.OFF,
		"planning": _planning,
		"scanning": _scan_active,
		"locked_by": locked_by,
		"busy": _planning or _scan_active or not locked_by.is_empty(),
	}


## Simulate one action on the tool's own raster, refusing while the tool is busy.
## Returns a compact leg summary so a playtest or an editor probe can inspect the
## movement model without reaching into the shared instances.
func try_simulate(start_state: Dictionary, action: Dictionary) -> Dictionary:
	var state := get_lock_state()
	if bool(state.get("busy", true)):
		return {"ok": false, "busy": state}
	if _motion == null or _grid == null:
		return {"ok": false, "reason": "no raster; open the tool first"}
	var leg = _motion.call("simulate", start_state, action, &"probe")
	if leg == null:
		return {"ok": false, "reason": "leg rejected", "busy": state}
	return {
		"ok": true,
		"start_cell": str(leg.start_cell),
		"end_cell": str(leg.end_cell),
		"frames": leg.frames,
		"end_mode": leg.end_mode,
		"end_position": str(leg.end_position),
		"action": String(leg.action),
	}


# --- internals ---------------------------------------------------------------

func _open() -> void:
	if _player == null:
		return
	_check_room_change()
	_mode = Mode.PICK
	_base_source = _player.call("get_input_source") as RefCounted
	_player.call("set_input_source", _neutral)
	set_process(true)
	set_physics_process(true)
	_scan_attempts = 0
	_scan_retry_ms = 0
	if not _begin_scan():
		_close()
		return
	_status_line = "SCANNING"
	_status_color = HINT_COLOR
	queue_redraw()


func _close() -> void:
	_stop_driver()
	_mode = Mode.OFF
	_scan_active = false
	_scan_retry_ms = 0
	_pending_start = Vector2.INF
	_pending_goal = Vector2.INF
	set_physics_process(false)
	if _player != null and _base_source != null:
		_player.call("set_input_source", _base_source)
	_status_line = ""
	queue_redraw()


func _neutral_source() -> RefCounted:
	return _neutral


func _move_cursor(step: Vector2i, fast: bool) -> void:
	var scale_step := 4 if fast else 1
	_cursor_cell += step * scale_step
	if _grid != null and _grid.is_built():
		_cursor_cell = _clamp_cursor(_cursor_cell)
	queue_redraw()


func _clamp_cursor(cell: Vector2i) -> Vector2i:
	var rect := _grid.nav_rect
	return Vector2i(
		clampi(cell.x, rect.position.x, rect.end.x - 1),
		clampi(cell.y, rect.position.y, rect.end.y - 1)
	)


func _set_start_here() -> void:
	if _grid == null:
		return
	var cell := _grid.find_goal_cell(_grid.cell_to_world(_cursor_cell), 6)
	if cell == AutopilotGrid.INVALID_CELL:
		_status_line = "NO FOOTHOLD HERE"
		_status_color = BAD_COLOR
		return
	_start_cell = cell
	_status_line = "START PINNED"
	_status_color = START_COLOR
	queue_redraw()


func _set_goal_here() -> void:
	if _grid == null:
		return
	var cell := _grid.find_goal_cell(_grid.cell_to_world(_cursor_cell), 8)
	if cell == AutopilotGrid.INVALID_CELL:
		_status_line = "NO FOOTHOLD HERE"
		_status_color = BAD_COLOR
		return
	_goal_cell = cell
	_status_line = "GOAL PINNED"
	_status_color = GOAL_COLOR
	queue_redraw()


func _clear_points() -> void:
	_stop_driver()
	_start_cell = AutopilotGrid.INVALID_CELL
	_goal_cell = AutopilotGrid.INVALID_CELL
	_route = null
	_deviation_history.clear()
	_last_deviation = {}
	_status_line = "CLEARED"
	_status_color = HINT_COLOR
	queue_redraw()


## The raster exists only while the tool is open: nothing is built on room entry
## or exit, so walking between rooms costs nothing.
func _ensure_ready() -> bool:
	if _player == null or not is_instance_valid(_player):
		return false
	if _planning:
		# The planner owns the raster and the simulator while a worker runs.
		return _grid != null and _grid.is_built()
	return _grid != null and _grid.is_built()


## Abilities can be unlocked (or revoked by a progression sync) between plans;
## the raster does not depend on them, so refresh them in place instead of
## rebuilding the whole room map.
func _refresh_abilities() -> void:
	if _motion == null or _player == null:
		return
	_motion.dash_enabled = _player_has_ability(&"dash")
	_motion.climb_enabled = _player_has_ability(&"climb")
	_motion.dash_definition = _dash_definition()


## Begin the scan: rasterize the current room over several frames so the sweep is
## visible and no single frame stalls.
func _begin_scan() -> bool:
	var room_rect := _current_room_rect()
	if room_rect.size.x <= 0.0 or room_rect.size.y <= 0.0:
		_status_line = "NO ACTIVE ROOM"
		_status_color = BAD_COLOR
		return false
	if _movement_profile() == null:
		_status_line = "PLAYER HAS NO MOVEMENT PROFILE"
		_status_color = BAD_COLOR
		return false
	var space := _player.get_world_2d().direct_space_state
	if space == null:
		return false
	var cell_rect := Rect2i(
		Vector2i(
			floori(room_rect.position.x / float(AutopilotGrid.NAV_CELL_SIZE)),
			floori(room_rect.position.y / float(AutopilotGrid.NAV_CELL_SIZE))
		),
		Vector2i(
			roundi(room_rect.size.x / float(AutopilotGrid.NAV_CELL_SIZE)),
			roundi(room_rect.size.y / float(AutopilotGrid.NAV_CELL_SIZE))
		)
	)
	var grid := GRID.new() as AutopilotGrid
	_apply_body_shape(grid)
	grid.collision_mask = _player.collision_mask
	if not grid.begin_build(
		space,
		cell_rect,
		_collect_zone_rects(&"ladder_zone"),
		_collect_zone_rects(&"hazard_zone")
	):
		return false
	_grid = grid
	_motion = null
	_planner = null
	_grid_footholds = 0
	_scan_active = true
	_scan_progress = 0.0
	_scan_fade = 1.0
	_scan_done_ms = 0
	_room_id = _current_room_id()
	_cursor_cell = _clamp_cursor(grid.world_to_cell(_player.global_position))
	_status_line = "SCANNING"
	_status_color = HINT_COLOR
	return true


## The raster is complete: build the simulator and planner around it.
func _finish_scan() -> void:
	_scan_active = false
	_scan_done_ms = Time.get_ticks_msec()
	var profile := _movement_profile()
	_motion = MOTION.new() as AutopilotMotion
	_motion.configure(_grid, profile, _dash_definition(), float(Engine.physics_ticks_per_second))
	_motion.dash_enabled = _player_has_ability(&"dash")
	_motion.climb_enabled = _player_has_ability(&"climb")
	_planner = PLANNER.new() as AutopilotPlanner
	_planner.configure(_grid, _motion)
	_grid_footholds = 0
	for cy: int in range(_grid.nav_rect.position.y, _grid.nav_rect.end.y):
		for cx: int in range(_grid.nav_rect.position.x, _grid.nav_rect.end.x):
			if _grid.cell_is_standable(Vector2i(cx, cy)):
				_grid_footholds += 1
	_grid_built_ms = Time.get_ticks_msec()
	if _grid_footholds == 0 and _scan_attempts < 2:
		# The room's collision may not be registered yet; scan again shortly.
		_scan_attempts += 1
		_scan_retry_ms = Time.get_ticks_msec() + 250
		_status_line = "SCANNING  (room not ready)"
		return
	_scan_attempts = 0
	_status_line = "READY  %d footholds" % _grid_footholds
	_status_color = HINT_COLOR
	_cursor_cell = _clamp_cursor(_grid.world_to_cell(_player.global_position))
	if _pending_start.is_finite():
		var pending := _pending_start
		_pending_start = Vector2.INF
		set_start(pending)
	if _pending_goal.is_finite():
		var pending := _pending_goal
		_pending_goal = Vector2.INF
		set_goal(pending)
	queue_redraw()


func _apply_body_shape(grid: AutopilotGrid) -> void:
	var shape_node := _player.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape_node == null or shape_node.shape is not RectangleShape2D:
		return
	var rectangle := shape_node.shape as RectangleShape2D
	grid.body_size = rectangle.size
	grid.body_offset = shape_node.position


func _movement_profile() -> MovementProfile:
	if _player == null or not "tuning" in _player:
		return null
	return _player.get("tuning") as MovementProfile


func _dash_definition() -> Resource:
	if not _player_has_ability(&"dash"):
		return null
	var loadout := _player.get_node_or_null("AbilityLoadout")
	if loadout == null or not loadout.has_method("get_dash_definition"):
		return null
	return loadout.call("get_dash_definition") as Resource


## Abilities the actor really owns; the shipped game unlocks Dash and Climb
## through progression, so a plan must not assume them.
func _player_has_ability(ability_id: StringName) -> bool:
	if _player == null or not _player.has_method("has_ability"):
		return false
	return bool(_player.call("has_ability", ability_id))


func _collect_zone_rects(group: StringName) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	for node: Node in get_tree().get_nodes_in_group(group):
		var node_2d := node as Node2D
		if node_2d == null:
			continue
		for child: Node in node_2d.get_children():
			var shape_node := child as CollisionShape2D
			if shape_node == null or not shape_node.shape is RectangleShape2D:
				continue
			var rectangle := shape_node.shape as RectangleShape2D
			var size := rectangle.size * shape_node.global_scale.abs()
			rects.append(Rect2(shape_node.global_position - size * 0.5, size))
	return rects


func _current_room_id() -> String:
	if _world_root == null:
		return ""
	var runtime := _world_root.get_node_or_null("WorldRuntime")
	if runtime == null or not runtime.has_method("get_current_room_id"):
		return ""
	return String(runtime.call("get_current_room_id"))


func _current_room_rect() -> Rect2:
	if _world_root == null:
		return Rect2()
	var room_id := _current_room_id()
	if room_id.is_empty():
		return Rect2()
	var world: Resource = _world_root.get("world_data")
	if world == null or not world.has_method("get_room_pixel_rect"):
		return Rect2()
	return Rect2(world.call("get_room_pixel_rect", room_id))


## Plan on a worker thread so the game keeps running: A* searches the rasterized
## room while the character stands (or falls) at full frame rate.
func _request_plan(teleport: bool) -> bool:
	if _planning:
		return false
	if _scan_active:
		_status_line = "SCANNING  %d%%" % roundi(_scan_progress * 100.0)
		_plan_requested = true
		return false
	if not _ensure_ready():
		return false
	if _grid == null or not _grid.is_built():
		return false
	if _start_cell == AutopilotGrid.INVALID_CELL or _goal_cell == AutopilotGrid.INVALID_CELL:
		_status_line = "SET START (SPACE) AND GOAL (X)"
		_status_color = BAD_COLOR
		return false
	_refresh_abilities()
	_stop_driver()
	_last_deviation = {}
	if teleport:
		_plan_attempts = 0
	var start_position := _grid.cell_to_world(_start_cell)
	if teleport and _player.global_position.distance_to(start_position) > 8.0:
		_player.call("respawn_at", start_position)
	_mode = Mode.PICK
	_player.call("set_input_source", _neutral)
	_plan_start_state = _player_state()
	_plan_is_initial = teleport
	_plan_thread_route = null
	_plan_thread_done = false
	_plan_started_ms = Time.get_ticks_msec()
	_planned_seconds = 0.0
	_planning = true
	_status_line = "PLANNING"
	_status_color = HINT_COLOR
	_plan_task_id = WorkerThreadPool.add_task(
		_run_plan_task.bind(_plan_start_state, _grid.cell_to_world(_goal_cell)),
		false,
		"autopilot route"
	)
	queue_redraw()
	return true


## Worker body: pure array math, no scene-tree access.
func _run_plan_task(from_state: Dictionary, goal_world: Vector2) -> void:
	_plan_thread_route = _planner.plan(from_state, goal_world)


func _poll_plan() -> void:
	if not _planning:
		return
	if _plan_task_id >= 0 and not WorkerThreadPool.is_task_completed(_plan_task_id):
		_status_line = "PLANNING  %.1fs" % (float(Time.get_ticks_msec() - _plan_started_ms) / 1000.0)
		return
	WorkerThreadPool.wait_for_task_completion(_plan_task_id)
	_plan_task_id = -1
	_planning = false
	_planned_seconds = float(Time.get_ticks_msec() - _plan_started_ms) / 1000.0
	if _mode == Mode.OFF:
		_plan_thread_route = null
		return
	_apply_plan()


func _apply_plan() -> void:
	var route: AutopilotRoute = _plan_thread_route
	_plan_thread_route = null
	var planned_position := Vector2(_plan_start_state.get("position", Vector2.ZERO))
	if (
		_player != null
		and _player.global_position.distance_to(planned_position) > 12.0
		and _plan_attempts < 2
	):
		# The character kept moving while A* ran: plan again from where it is.
		_plan_attempts += 1
		_status_line = "PLANNING  (moved, retry %d)" % _plan_attempts
		_request_plan(false)
		return
	_route = route
	if route == null or route.is_empty():
		if _standing_at_goal():
			_status_line = "ARRIVED  (already there)"
			_status_color = START_COLOR
			_mode = Mode.PICK
			queue_redraw()
			return
		_status_line = "NO ROUTE (%.1fs)" % _planned_seconds
		_status_color = BAD_COLOR
		queue_redraw()
		return
	var driver := DRIVER.new() as AutopilotDriver
	driver.configure(_player, _base_source)
	driver.set_tolerance(10.0)
	driver.route_finished.connect(_on_route_finished)
	driver.route_deviation.connect(_on_route_deviation)
	driver.set_route(route)
	_driver = driver
	_last_reported_leg = -1
	if not _player.has_method("set_input_source") or not bool(_player.call("set_input_source", driver)):
		_stop_driver()
		return
	_mode = Mode.RUNNING
	_progress_position = _player.global_position
	_progress_ms = Time.get_ticks_msec()
	_stuck_count = 0
	_finish_attempts = 0
	_status_line = "RUN  (planned %.1fs)" % _planned_seconds
	_status_color = HINT_COLOR
	queue_redraw()


func _player_state() -> Dictionary:
	var debug: Dictionary = {}
	if _player.has_method("get_debug_state"):
		debug = _player.call("get_debug_state")
	var mode := LEG.MODE_GROUND
	var motion_state := int(debug.get("state", 0))
	var wall_direction := int(debug.get("wall_direction", 0))
	if _player.has_method("is_on_ladder") and bool(_player.call("is_on_ladder")):
		# The controller reports NORMAL while hanging on a ladder, so the public
		# ladder query is the reliable source here.
		mode = LEG.MODE_LADDER
	elif motion_state == 2 or motion_state == 3:
		mode = LEG.MODE_WALL_LEFT if wall_direction < 0 else LEG.MODE_WALL_RIGHT
	elif not _player.is_on_floor():
		mode = LEG.MODE_AIR
	return {
		"position": _player.global_position,
		"velocity": _player.velocity,
		"mode": mode,
		"dash_charge": _player_has_ability(&"dash"),
		"stamina": float(debug.get("stamina", 110.0)),
	}


func _stop_driver() -> void:
	_replan_pending = false
	if _driver != null:
		_driver.stop()
		_driver = null
	if _player != null and _boot_source() != null:
		_player.call("set_input_source", _boot_source())
	if _mode == Mode.RUNNING:
		_mode = Mode.PICK
		_cursor_cell = _clamp_cursor(_grid.world_to_cell(_player.global_position)) \
			if _grid != null else _cursor_cell


func _boot_source() -> RefCounted:
	return _base_source


func _on_route_finished(reached: bool) -> void:
	# Deferred: the driver emits from inside its own get_intent() call.
	call_deferred("_finish_route", reached)


func _on_route_deviation(at_position: Vector2) -> void:
	if _driver != null:
		_last_deviation = {
			"leg": _driver.last_deviation_leg,
			"action": _driver.last_deviation_action,
			"tick": _driver.last_deviation_tick,
			"expected": _driver.last_expected,
			"actual": at_position,
			"leg_start": _driver.last_leg_start,
			"entry_errors": _driver.leg_entry_errors.duplicate(),
			"trace": _driver.trace.duplicate(),
		}
		_deviation_history.append(_last_deviation)
		if _deviation_history.size() > 8:
			_deviation_history.remove_at(0)
	call_deferred("_replan_after_drift", at_position)


func _finish_route(reached: bool) -> void:
	var goal_position := Vector2.ZERO
	if _grid != null and _goal_cell != AutopilotGrid.INVALID_CELL:
		goal_position = _grid.cell_to_world(_goal_cell)
	var arrived := reached and _standing_at_goal()
	if arrived and not _course.is_empty() and _course_index + 1 < _course.size():
		_course_index += 1
		_goal_cell = _grid.find_goal_cell(_course[_course_index], 10)
		_status_line = "WAYPOINT %d/%d" % [_course_index + 1, _course.size()]
		_status_color = HINT_COLOR
		_request_plan(false)
		return
	if not arrived and _mode == Mode.RUNNING:
		_finish_attempts += 1
		if _finish_attempts <= 3:
			_status_line = "SHORT OF GOAL - RECOVERING"
			_status_color = BAD_COLOR
			_driver = null
			_player.call("set_input_source", _neutral)
			_replan_pending = true
			queue_redraw()
			return
	var legs := 0 if _route == null else _route.get_leg_count()
	var frames := 0 if _route == null else _route.get_frames()
	var ticks := maxf(float(Engine.physics_ticks_per_second), 1.0)
	_status_line = "%s  %d legs  %.1fs" % [
		"ARRIVED" if arrived else "STOPPED SHORT",
		legs,
		float(frames) / ticks,
	]
	_status_color = START_COLOR if arrived else BAD_COLOR
	_mode = Mode.PICK
	if _player != null and _base_source != null:
		_player.call("set_input_source", _base_source)
	_driver = null
	queue_redraw()


func _replan_after_drift(at_position: Vector2) -> void:
	_driver = null
	_status_line = "DRIFT AT %d,%d - RECOVERING" % [roundi(at_position.x), roundi(at_position.y)]
	_status_color = BAD_COLOR
	if _mode != Mode.RUNNING:
		return
	# Mid-air states plan badly. Let the character land first, then replan from a
	# foothold; the tool keeps ownership of the input meanwhile.
	_player.call("set_input_source", _neutral)
	_replan_pending = true
	queue_redraw()


func _sync_status() -> void:
	if _mode == Mode.RUNNING and _driver != null:
		_check_progress()
		var progress := _driver.get_progress()
		var leg := int(progress.get("leg", 0))
		if leg != _last_reported_leg:
			_last_reported_leg = leg
			_status_line = "RUN %d/%d  %s" % [
				leg + 1,
				int(progress.get("leg_count", 0)),
				String(progress.get("code", "")),
			]
			_status_color = HINT_COLOR
			queue_redraw()
	if _mode == Mode.PICK and _route != null:
		queue_redraw()


func _check_progress() -> void:
	if _player == null:
		return
	if _replan_pending:
		# Recovery is already in charge; waiting is not being stuck.
		_progress_ms = Time.get_ticks_msec()
		return
	var now := Time.get_ticks_msec()
	var body_position := _player.global_position
	if body_position.distance_to(_progress_position) > 4.0:
		_progress_position = body_position
		_progress_ms = now
		return
	if _progress_ms == 0:
		_progress_ms = now
		return
	if now - _progress_ms < 1500:
		return
	_progress_ms = now
	_stuck_count += 1
	if _stuck_count > 1:
		_stop_driver()
		_mode = Mode.PICK
		_status_line = "STUCK - STOPPED"
		_status_color = BAD_COLOR
		queue_redraw()
		return
	# Hand the character back a living input source, then replan from a foothold.
	_stop_driver()
	_driver = null
	if _player != null:
		_player.call("set_input_source", _neutral)
	_replan_pending = true
	_status_line = "STUCK - RECOVERING"
	_status_color = BAD_COLOR


func _draw() -> void:
	if _mode == Mode.OFF:
		return
	if _scan_active or _scan_fade > 0.0:
		_draw_scan()
	if _scan_active:
		_draw_hint()
		return
	if _route != null:
		_draw_route(_route)
	if _goal_cell != AutopilotGrid.INVALID_CELL:
		_draw_pin(_goal_cell, GOAL_COLOR, "B")
	if _start_cell != AutopilotGrid.INVALID_CELL:
		_draw_pin(_start_cell, START_COLOR, "A")
	if _mode == Mode.PICK:
		_draw_cursor()
	if _grid != null and _grid.is_built():
		_draw_hint()


## Room-reveal style sweep: footholds appear under the scan line, and a soft
## band trails the leading edge. The raster is built slice by slice, so the
## effect is the actual progress rather than decoration.
func _draw_scan() -> void:
	if _grid == null:
		return
	var alpha := _scan_fade
	if _scan_active:
		alpha = 1.0
	var scan_y := _grid.build_scan_y()
	var nav := _grid.nav_rect
	var left := float(nav.position.x * AutopilotGrid.NAV_CELL_SIZE)
	var right := float(nav.end.x * AutopilotGrid.NAV_CELL_SIZE)
	var top := float(nav.position.y * AutopilotGrid.NAV_CELL_SIZE)
	var bottom := float(nav.end.y * AutopilotGrid.NAV_CELL_SIZE)
	var dot_color := Color(0.42, 0.95, 0.82, 0.85 * alpha)
	var one_way_color := Color(0.45, 0.72, 1.0, 0.85 * alpha)
	for cy: int in range(nav.position.y, nav.end.y):
		var row_y := float(cy * AutopilotGrid.NAV_CELL_SIZE)
		if row_y > scan_y:
			break
		for cx: int in range(nav.position.x, nav.end.x):
			var cell := Vector2i(cx, cy)
			if not _grid.cell_is_standable(cell):
				continue
			var color := dot_color
			if _grid.cell_has_one_way(cell):
				color = one_way_color
			draw_rect(
				Rect2(Vector2(float(cx * AutopilotGrid.NAV_CELL_SIZE), row_y) + Vector2(3.0, 2.0), Vector2(2.0, 2.0)),
				color
			)
	if not _scan_active:
		return
	var band_top := clampf(scan_y - 12.0, top, bottom)
	draw_rect(Rect2(left, band_top, right - left, 6.0), Color(0.35, 0.95, 0.85, 0.10))
	draw_rect(Rect2(left, band_top + 6.0, right - left, 6.0), Color(0.35, 0.95, 0.85, 0.22))
	draw_line(
		Vector2(left, scan_y),
		Vector2(right, scan_y),
		Color(0.78, 1.0, 0.95, 0.95),
		1.0
	)


func _draw_route(route: AutopilotRoute) -> void:
	for leg: AutopilotLeg in route.legs:
		var color := leg.action_color()
		var previous := to_local(leg.get_sample(0))
		for index: int in range(1, leg.samples.size()):
			var point := to_local(leg.samples[index])
			draw_line(previous, point, color, 0.9)
			previous = point
		draw_circle(to_local(leg.start_position), 1.1, color)


func _draw_pin(cell: Vector2i, color: Color, letter: String) -> void:
	var anchor := to_local(_grid.cell_to_world(cell))
	var points := PackedVector2Array([
		anchor + Vector2(0.0, -5.0),
		anchor + Vector2(2.5, -2.0),
		anchor,
		anchor + Vector2(-2.5, -2.0),
	])
	draw_colored_polygon(points, color)
	draw_line(anchor, anchor + Vector2(0.0, 2.0), color, 1.0)
	draw_string(
		ThemeDB.fallback_font,
		anchor + Vector2(3.0, -4.0),
		letter,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		7,
		color
	)


func _draw_cursor() -> void:
	var anchor := to_local(_grid.cell_to_world(_cursor_cell)) + Vector2(0.0, -4.0)
	draw_line(anchor + Vector2(-4.0, 0.0), anchor + Vector2(-1.5, 0.0), CURSOR_COLOR, 1.0)
	draw_line(anchor + Vector2(1.5, 0.0), anchor + Vector2(4.0, 0.0), CURSOR_COLOR, 1.0)
	draw_line(anchor + Vector2(0.0, -4.0), anchor + Vector2(0.0, -1.5), CURSOR_COLOR, 1.0)
	draw_line(anchor + Vector2(0.0, 1.5), anchor + Vector2(0.0, 4.0), CURSOR_COLOR, 1.0)


func _draw_hint() -> void:
	var origin := to_local(Vector2(_grid.nav_rect.position) * float(AutopilotGrid.NAV_CELL_SIZE))
	var font := ThemeDB.fallback_font
	var first := _status_line
	if first.is_empty():
		first = "AUTO ROUTE"
	draw_string(
		font,
		origin + Vector2(4.0, 10.0),
		first,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		7,
		_status_color
	)
	var second := "ARROWS MOVE  SPACE A  X B  ENTER RUN  BACKSPACE CLEAR  F4 EXIT"
	if _mode == Mode.RUNNING:
		second = "RUNNING  F4 STOP"
	draw_string(
		font,
		origin + Vector2(4.0, 18.0),
		second,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		6,
		HINT_COLOR
	)
