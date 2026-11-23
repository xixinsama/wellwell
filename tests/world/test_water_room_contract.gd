extends Node

## Contract and flow test for the baked water hall.
##
## It binds a real WaterField to the generated room (same call the world session
## makes), lets the sluice gate open and the pools settle, and checks that water
## only starts moving after the gate opens and that the volume is conserved.

const ROOM_DATA := preload("res://resources/rooms/generated/water_hall.tres")
const RUNTIME_SCENE := preload("res://scenes/rooms/generated/water_hall/runtime.tscn")
const TERRAIN_SCENE := preload("res://scenes/rooms/generated/water_hall/terrain.tscn")
const WATER_FIELD := preload("res://addons/fluid_kit/runtime/water/water_field.gd")
const WORLD := preload("res://resources/worlds/test_world.tres")
const WORLD_VALIDATION := preload("res://addons/platformer_kit/world/data/world_validation.gd")

const ROOM_ORIGIN_CHUNK := Vector2i(0, 1)
const STEP := 1.0 / 120.0


func run() -> Array[String]:
	var failures: Array[String] = []
	_assert_world_references(failures)
	_assert_baked_room(failures)
	_assert_water_flow(failures)
	return failures


func _assert_world_references(failures: Array[String]) -> void:
	var report: Dictionary = WORLD_VALIDATION.validate_world_report(WORLD)
	for error: String in report.get("errors", []):
		failures.append("test world is invalid: %s" % error)
	if String(WORLD.start_room_id) != "water_hall":
		failures.append("test world does not start in the water hall: %s" % WORLD.start_room_id)
	if not WORLD.has_room("water_hall"):
		failures.append("test world does not reference the water hall")
	if not ROOM_DATA.spawn_ids.has("start"):
		failures.append("water hall has no start spawn")
	if ROOM_DATA.room_size_chunks != Vector2i.ONE:
		failures.append("water hall is not a single chunk: %s" % str(ROOM_DATA.room_size_chunks))


func _assert_baked_room(failures: Array[String]) -> void:
	var runtime := RUNTIME_SCENE.instantiate()
	for node_name: String in ["WaterBasinA", "WaterBasinB", "SluiceGate", "HallLight"]:
		if runtime.find_child(node_name, true, false) == null:
			failures.append("baked water hall is missing %s" % node_name)
	var light_count := 0
	for child: Node in runtime.find_children("*", "Node2D", true, false):
		if child.has_method("get_energy_at"):
			light_count += 1
	if light_count < 2:
		failures.append("baked water hall has fewer than two fog lights: %d" % light_count)
	runtime.free()


func _assert_water_flow(failures: Array[String]) -> void:
	var runtime := RUNTIME_SCENE.instantiate() as Node2D
	var terrain := TERRAIN_SCENE.instantiate() as Node2D
	var origin := Vector2(ROOM_ORIGIN_CHUNK) * Vector2(320.0, 180.0)
	runtime.position = origin
	terrain.position = origin
	add_child(runtime)
	add_child(terrain)
	var field := WATER_FIELD.new() as Node2D
	add_child(field)
	if not bool(field.call("bind_room_with_origin", ROOM_DATA, terrain, ROOM_ORIGIN_CHUNK)):
		failures.append("water field refused to bind to the water hall")
		_cleanup(field, runtime, terrain)
		return

	var gate := runtime.find_child("SluiceGate", true, false)
	var volume_start := float(field.call("get_debug_state").get("volume", 0.0))
	if volume_start <= 0.0:
		failures.append("water hall started without water")
	# Left tank has water, right basin starts dry (local x 64 and 240, world y offset).
	if float(field.call("get_surface_y_at", 64.0)) == INF:
		failures.append("tank A has no water at x=64")
	if float(field.call("get_surface_y_at", 240.0)) != INF:
		failures.append("basin B was not dry before the gate opened")

	# The gate is closed for a moment: the right basin must stay dry.
	for _frame: int in 60:
		field.call("_physics_process", STEP)
	if float(field.call("get_surface_y_at", 240.0)) != INF:
		failures.append("water crossed the closed gate")

	# Open the gate and let the pools settle.
	for _frame: int in 900:
		if gate != null:
			gate.call("_process", STEP)
		field.call("_physics_process", STEP)
	var left_surface := float(field.call("get_surface_y_at", 64.0))
	var right_surface := float(field.call("get_surface_y_at", 240.0))
	var volume_end := float(field.call("get_debug_state").get("volume", 0.0))
	if left_surface == INF:
		failures.append("tank A drained completely")
	if right_surface == INF:
		failures.append("basin B never received water")
	elif right_surface < 300.0 or right_surface > 340.0:
		failures.append("basin B settled at an unexpected height: %.1f" % right_surface)
	if left_surface != INF and left_surface < 280.0:
		failures.append("tank A did not drain towards the spill lip: %.1f" % left_surface)
	if absf(volume_end - volume_start) > volume_start * 0.02:
		failures.append(
			"water volume was not conserved: start=%.1f end=%.1f" % [volume_start, volume_end]
		)
	_cleanup(field, runtime, terrain)


func _cleanup(field: Node, runtime: Node, terrain: Node) -> void:
	field.queue_free()
	runtime.queue_free()
	terrain.queue_free()
