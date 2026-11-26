extends Node2D
## Runs the solver across the benchmark rooms in the real game.
##
## It switches to each room, applies that room's dash and climb permissions,
## scans the live collision through the auto-route tool, plans from the room's A
## waypoint to its B waypoint, waits for the run, and records whether it arrived
## and how many replans it needed. With [member autostart] it starts by itself
## when the session lands in a benchmark room and draws the table on screen.

signal run_finished(results: Array)

const SETTLE_FRAMES := 14
const SCAN_TIMEOUT_FRAMES := 600
const ROOM_TIMEOUT_FRAMES := 900
const ARRIVE_TOLERANCE := 7.0
const SNAPSHOT = preload("res://addons/platformer_kit/save/save_snapshot.gd")

@export var autostart := true
var autostart_specs: Array[Dictionary] = []
var tool_path := NodePath("../AutoRoute")
var player_path := NodePath("../Player")
var world_runtime_path := NodePath("../WorldRuntime")
var bias := 0.0

var _session: Node
var _world: Resource
var _rooms: Array[Dictionary] = []
var _results: Array[Dictionary] = []
var _index := 0
var _phase := 0
var _frames := 0
var _running := false
var _autostarted := false
var _started_ms := 0


func configure(session: Node, world: Resource, rooms: Array[Dictionary], plan_bias: float = 0.0) -> void:
	_session = session
	_world = world
	_rooms = rooms
	bias = plan_bias


func start_run() -> bool:
	if _session == null or _world == null or _rooms.is_empty():
		return false
	_results.clear()
	_index = 0
	_phase = 0
	_frames = 0
	_running = true
	_started_ms = Time.get_ticks_msec()
	_begin_room()
	return true


func is_running() -> bool:
	return _running


func get_results() -> Array[Dictionary]:
	return _results


func _process(_delta: float) -> void:
	if not _running:
		_maybe_autostart()
		queue_redraw()
		return
	_frames += 1
	match _phase:
		1:
			if _frames >= SETTLE_FRAMES:
				_prepare_room()
		2:
			_wait_for_scan()
		3:
			_wait_for_run()
	if _frames > ROOM_TIMEOUT_FRAMES and _phase != 0:
		_record_failure("room timeout")
		_next_room()
	queue_redraw()


func _maybe_autostart() -> void:
	if not autostart or _autostarted:
		return
	if _session == null:
		# The runner lives beside the player, so the world session is its parent.
		_session = get_parent()
	if _session == null:
		return
	var runtime := _session.get_node_or_null(world_runtime_path)
	if runtime == null:
		return
	var world: Resource = runtime.get("world_data")
	if world == null:
		return
	var room_id := String(runtime.call("get_current_room_id"))
	if not room_id.begins_with("bench_"):
		return
	_world = world
	position = Rect2(world.call("get_room_pixel_rect", room_id)).position
	if autostart_specs.is_empty():
		autostart_specs = _specs_from_benchmark_data()
	if autostart_specs.is_empty():
		return
	_autostarted = true
	configure(_session, _world, autostart_specs)
	start_run()


func _begin_room() -> void:
	if _index >= _rooms.size():
		_finish()
		return
	var room_id := String(_rooms[_index].room_id)
	var runtime := _session.get_node_or_null(world_runtime_path)
	var switched := false
	if runtime != null and runtime.has_method("travel_to_door"):
		switched = bool(runtime.call("travel_to_door", room_id, "start"))
	if not switched:
		var snapshot = SNAPSHOT.new()
		snapshot.slot = 1
		snapshot.world_id = _world.world_id
		snapshot.current_room_id = room_id
		snapshot.respawn_room_id = room_id
		switched = bool(_session.call("start_selected_snapshot", snapshot, _world))
	_frames = 0
	_phase = 1 if switched else 5
	if not switched:
		_record_failure("room did not start")
		_next_room()


func _prepare_room() -> void:
	var spec: Dictionary = _rooms[_index]
	var tool := _tool()
	var player := _player()
	if tool == null or player == null:
		_record_failure("missing tool or player")
		_next_room()
		return
	var runtime := _session.get_node_or_null(world_runtime_path)
	if runtime != null and String(runtime.call("get_current_room_id")) != String(spec.room_id):
		if _frames < SETTLE_FRAMES * 8:
			return
		_record_failure("room never became current")
		_next_room()
		return
	_apply_abilities(player, spec)
	position = Rect2(_world.call("get_room_pixel_rect", String(spec.room_id))).position
	player.call("respawn_at", _waypoint(spec, "start_cell"))
	(tool.get("_deviation_history") as Array).clear()
	tool.call("close_tool")
	tool.call("open_tool")
	_frames = 0
	_phase = 2


func _wait_for_scan() -> void:
	var tool := _tool()
	if tool == null:
		_record_failure("tool vanished")
		_next_room()
		return
	if bool(tool.get("_scan_active")) or int(tool.get("_grid_footholds")) <= 0:
		if _frames > SCAN_TIMEOUT_FRAMES:
			_record_failure("empty raster")
			_next_room()
		return
	var spec: Dictionary = _rooms[_index]
	tool.call("set_start", _waypoint(spec, "start_cell"))
	tool.call("set_goal", _waypoint(spec, "goal_cell"))
	var planner = tool.get("_planner")
	if planner != null:
		planner.set("stability_bias", bias)
	if not bool(tool.call("plan_and_run")):
		_record_failure("plan refused")
		_next_room()
		return
	_frames = 0
	_phase = 3


func _wait_for_run() -> void:
	var tool := _tool()
	if tool == null:
		_record_failure("tool vanished")
		_next_room()
		return
	if bool(tool.get("_planning")) or int(tool.get("_mode")) == 2:
		return
	var spec: Dictionary = _rooms[_index]
	var player := _player()
	var distance := 1.0e9
	if player != null:
		distance = Vector2(player.global_position).distance_to(_waypoint(spec, "goal_cell"))
	_results.append({
		"room_id": String(spec.room_id),
		"ok": distance <= ARRIVE_TOLERANCE,
		"replans": (tool.get("_deviation_history") as Array).size(),
		"distance": snappedf(distance, 0.1),
		"plan_seconds": snappedf(float(tool.get("_planned_seconds")), 0.001),
		"status": String(tool.call("get_status_line")),
	})
	_next_room()


func _record_failure(reason: String) -> void:
	_results.append({
		"room_id": String(_rooms[_index].room_id),
		"ok": false,
		"replans": 0,
		"distance": -1.0,
		"plan_seconds": 0.0,
		"status": reason,
	})
	_next_room()


func _next_room() -> void:
	var tool := _tool()
	if tool != null:
		tool.call("close_tool")
	_index += 1
	_phase = 0
	_frames = 0
	_begin_room()


func _finish() -> void:
	_running = false
	var elapsed := float(Time.get_ticks_msec() - _started_ms) / 1000.0
	var passed := 0
	var replans := 0
	for result: Dictionary in _results:
		if bool(result.ok):
			passed += 1
		replans += int(result.replans)
	print("benchmark: %d/%d rooms, %d replans, %.1fs, bias %.1f" % [
		passed, _results.size(), replans, elapsed, bias,
	])
	for result: Dictionary in _results:
		print("  %-18s %s replans=%d plan=%.3fs dist=%.1f %s" % [
			String(result.room_id), "PASS" if bool(result.ok) else "FAIL",
			int(result.replans), float(result.plan_seconds), float(result.distance),
			String(result.status),
		])
	run_finished.emit(_results)


func _draw() -> void:
	if _results.is_empty() and not _running:
		return
	var line := 10.0
	var size := 168.0
	draw_rect(
		Rect2(Vector2(2.0, 2.0), Vector2(size, line * float(_results.size()) + 20.0)),
		Color(0.02, 0.06, 0.08, 0.8)
	)
	draw_string(
		ThemeDB.fallback_font, Vector2(6.0, 12.0),
		"BENCH %d/%d bias %.1f" % [_results.size(), _rooms.size(), bias],
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, 8, Color(0.7, 1.0, 0.95)
	)
	var y := 22.0
	for result: Dictionary in _results:
		var ok := bool(result.ok)
		draw_string(
			ThemeDB.fallback_font, Vector2(6.0, y),
			"%s %-13s r%d" % [
				"OK  " if ok else "FAIL",
				String(result.room_id).trim_prefix("bench_"),
				int(result.replans),
			],
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, 8,
			Color(0.55, 1.0, 0.75) if ok else Color(1.0, 0.6, 0.6)
		)
		y += line


func _waypoint(spec: Dictionary, key: String) -> Vector2:
	var cell: Vector2i = spec.get(key, Vector2i.ZERO)
	var rect := Rect2(_world.call("get_room_pixel_rect", String(spec.room_id)))
	return rect.position + Vector2(cell) * 8.0


func _tool() -> Node:
	if _session == null:
		return null
	var direct := _session.get_node_or_null(tool_path)
	return direct if direct != null else _session.find_child("AutoRoute", true, false)


func _player() -> Node2D:
	if _session == null:
		return null
	var direct := _session.get_node_or_null(player_path) as Node2D
	return direct if direct != null else _session.find_child("Player", true, false) as Node2D


func _apply_abilities(player: Node2D, spec: Dictionary) -> void:
	var loadout := player.get_node_or_null("AbilityLoadout")
	if loadout == null:
		return
	var progression = loadout.get("_progression")
	if progression == null:
		return
	for ability: StringName in [&"dash", &"climb"]:
		var want := bool(spec.get(String(ability), false))
		var have := bool(progression.call("has_ability", ability))
		if want and not have:
			progression.call("grant_ability", ability)
		elif have and not want and progression.has_method("revoke_ability"):
			progression.call("revoke_ability", ability)
	if loadout.has_method("synchronize_unlocked_abilities"):
		loadout.call("synchronize_unlocked_abilities")


func _specs_from_benchmark_data() -> Array[Dictionary]:
	var path := "res://tools/benchmark/benchmark_rooms.gd"
	if not ResourceLoader.exists(path):
		return []
	var rooms_script: Script = load(path) as Script
	if rooms_script == null:
		return []
	var built: Array[Dictionary] = []
	for spec: Dictionary in rooms_script.call("specs"):
		built.append({
			"room_id": "bench_%02d_%s" % [built.size(), String(spec.id)],
			"start_cell": spec.start,
			"goal_cell": spec.goal,
			"seconds": float(spec.seconds),
			"dash": bool(spec.dash),
			"climb": bool(spec.climb),
		})
	return built
