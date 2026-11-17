extends Node

## Regression test for the shape of the visible ripple on the 2D grid water.
##
## The landing never displaces the simulated body: the wobble is drawn by
## `water_grid.gdshader` from three ripple slots. Two things about that wave are easy
## to get wrong and both were wrong before:
##
##   1. a crest has to *travel*. The old model multiplied a static distance envelope by
##      `cos(distance - speed * age)`, which at small ages puts every column at nearly
##      the same phase, so the whole body lifted at once and the far side started
##      moving before the crest could physically reach it;
##   2. a crest has to come back off the walls of the body. There was no reflection at
##      all, so a pool never answered back.
##
## This test binds a real `WaterGrid` to the light lab room, splashes at the left end of
## the floor puddle and asserts the arrival order, the echo off the far wall, that the
## walls are the measured body edges, and that the three surface layers move in order.

const ROOM_DATA := preload("res://resources/rooms/generated/light_lab.tres")
const RUNTIME_SCENE := preload("res://scenes/rooms/generated/light_lab/runtime.tscn")
const TERRAIN_SCENE := preload("res://scenes/rooms/generated/light_lab/terrain.tscn")
const WATER_GRID := preload("res://addons/fluid_kit/runtime/water/water_grid.gd")

## The room is placed in the test world at this chunk, so the baked room content has
## to live at the same world origin the world session uses.
const ORIGIN_CHUNK := Vector2i(3, 0)
const STEP := 1.0 / 60.0
## Frames to let the pool overflow its rim and fill the floor puddle.
const SETTLE_STEPS := 600
## Landing speed of a hero jumping into water, px/s.
const IMPACT_SPEED := 300.0
## A displacement below this is under half a rendered pixel: invisible, so a column
## "has not moved" as far as the player is concerned.
const VISIBLE_OFFSET := 0.5
## Surfaces further apart than this are different water bodies.
const BODY_LEVEL_TOLERANCE := 6.0
## The widest body of this room (the floor puddle), so a room edit is caught here.
const BODY_MINIMUM := 150.0
## Tolerance on a predicted crest time, in seconds.
const TIME_TOLERANCE := 0.08


func run() -> Array[String]:
	var failures: Array[String] = []
	_assert_crest_travels_and_echoes(failures)
	return failures


func _assert_crest_travels_and_echoes(failures: Array[String]) -> void:
	var runtime := RUNTIME_SCENE.instantiate() as Node2D
	var terrain := TERRAIN_SCENE.instantiate() as Node2D
	var origin := Vector2(ORIGIN_CHUNK) * WATER_GRID.CHUNK_PIXELS
	runtime.position = origin
	terrain.position = origin
	add_child(runtime)
	add_child(terrain)
	var grid := WATER_GRID.new() as Node2D
	add_child(grid)
	if not bool(grid.call("bind_room_with_origin", ROOM_DATA, terrain, ORIGIN_CHUNK)):
		failures.append("water grid refused to bind to the light lab room")
		_cleanup(grid, runtime, terrain)
		return
	for _step: int in SETTLE_STEPS:
		grid.call("_physics_process", STEP)

	var bodies := _find_bodies(grid)
	if bodies.is_empty():
		failures.append("the light lab room has no water body after settling")
		_cleanup(grid, runtime, terrain)
		return
	var body := bodies[0]
	for candidate: Rect2 in bodies:
		if candidate.size.x > body.size.x:
			body = candidate
	if body.size.x < BODY_MINIMUM:
		failures.append("the widest lab body is only %.0f px, the room changed" % body.size.x)

	var cell := float(grid.get("cell_pixels"))
	var impact := body.position.x + cell * 0.5
	var surface := float(grid.call("get_surface_y_at", impact))
	if surface == INF:
		failures.append("the widest body has no surface at its left end")
		_cleanup(grid, runtime, terrain)
		return
	grid.call("request_splash_at", Vector2(impact, surface + 1.0), IMPACT_SPEED)

	var ripples: Array = grid.get("_ripples")
	if ripples.is_empty():
		failures.append("a landing recorded no ripple")
		_cleanup(grid, runtime, terrain)
		return
	var record: Vector4 = ripples[0]
	var span := _span(grid)
	var reach := _reach(grid)
	var speed := float(grid.get("ripple_speed"))
	var amplitude := float(grid.get("ripple_amplitude"))
	var damping := float(grid.get("ripple_damping"))

	# The walls are the measured edges of the body the splash landed in.
	if span.x > body.position.x + cell * 2.0 or span.y < body.end.x - cell * 2.0:
		failures.append(
			"the ripple walls %.0f..%.0f do not match the %.0f..%.0f body" %
			[span.x, span.y, body.position.x, body.end.x]
		)
	if reach < body.size.x * 0.9:
		failures.append(
			"the ripple reach %.0f px does not span the %.0f px body" % [reach, body.size.x]
		)

	# 1. Arrival order: the crest starts at the impact and reaches the far end later.
	var near_x := impact + 8.0
	var far_x := body.end.x - 6.0
	var near_arrival := WaterRipple.arrival(absf(near_x - impact), speed)
	var far_arrival := WaterRipple.arrival(absf(far_x - impact), speed)
	var early := near_arrival + 0.10
	if absf(_offset(early, near_x, record, span, speed, reach, amplitude, damping)) < VISIBLE_OFFSET:
		failures.append("the column next to the landing had not moved by %.2f s" % early)
	if early >= far_arrival and absf(
		_offset(early, far_x, record, span, speed, reach, amplitude, damping)
	) < VISIBLE_OFFSET:
		failures.append("the far column should already have moved by %.2f s" % early)
	if far_arrival > early + 0.2:
		if absf(_offset(early, far_x, record, span, speed, reach, amplitude, damping)) != 0.0:
			failures.append(
				"the far column moved at %.2f s, but its crest only arrives at %.2f s" %
				[early, far_arrival]
			)
	if absf(_offset(
		far_arrival + 0.25, far_x, record, span, speed, reach, amplitude, damping
	)) < VISIBLE_OFFSET:
		failures.append("the far column never moved, the crest did not reach the far wall")

	# 2. Reflection: the crest that hits the far wall comes back. Pick a column a third
	# of the body away from that wall, so the direct crest and the echo are separated.
	var wall := span.y
	var echo_x := wall - body.size.x / 3.0
	var direct_distance := absf(echo_x - impact)
	var echo_distance := absf(echo_x - (2.0 * wall - impact))
	var echo_arrival := WaterRipple.arrival(echo_distance, speed)
	if echo_arrival < WaterRipple.arrival(direct_distance, speed) + 0.25:
		failures.append(
			"the test column is too close to the wall to separate the echo (%.2f s)" % echo_arrival
		)
	if absf(_image_offset(
		echo_arrival - 0.10, echo_x, impact, wall, record, speed, reach, amplitude, damping
	)) != 0.0:
		failures.append("the echo arrived at %.2f s, before its crest" % (echo_arrival - 0.10))
	if absf(_image_offset(
		echo_arrival + 0.25, echo_x, impact, wall, record, speed, reach, amplitude, damping
	)) < VISIBLE_OFFSET:
		failures.append("no echo came back off the far wall")
	# The reflected aportation has to be visible in the total, not just in its own term.
	var total_at_echo := _offset(
		echo_arrival + 0.20, echo_x, record, span, speed, reach, amplitude, damping
	)
	var direct_at_echo := WaterRipple.body_offset_at(
		echo_arrival + 0.20, echo_x, impact, span, speed, reach, record.w, amplitude, damping, 0.0
	)
	if absf(total_at_echo - direct_at_echo) < VISIBLE_OFFSET:
		failures.append("the echo does not reach the surface at %.2f s" % (echo_arrival + 0.2))

	# 3. The three layers move one after the other, front first.
	var layers := _layer_first_motion(echo_x, record, span, speed, reach, amplitude, damping)
	if not (layers[2] < layers[1] and layers[1] < layers[0]):
		failures.append(
			"the layer crests do not arrive back to front: %s" % str(layers)
		)
	if absf(layers[1] - (WaterRipple.arrival(direct_distance, speed))) > TIME_TOLERANCE:
		failures.append(
			"the middle layer arrived at %.2f s instead of %.2f s" %
			[layers[1], WaterRipple.arrival(direct_distance, speed)]
		)
	_cleanup(grid, runtime, terrain)


func _offset(
	age: float, world_x: float, record: Vector4, span: Vector2,
	speed: float, reach: float, amplitude: float, damping: float
) -> float:
	return WaterRipple.body_offset_at(
		age, world_x, record.x, span, speed, reach, record.w, amplitude, damping
	)


## Displacement of the mirror image of the impact across `wall`: the echo alone.
func _image_offset(
	age: float, world_x: float, impact: float, wall: float, record: Vector4,
	speed: float, reach: float, amplitude: float, damping: float
) -> float:
	return WaterRipple.offset_at(
		age, absf(world_x - (2.0 * wall - impact)), speed, reach, record.w, amplitude, damping
	)


## First time each layer's crest lifts its column above the visibility threshold.
func _layer_first_motion(
	world_x: float, record: Vector4, span: Vector2,
	speed: float, reach: float, amplitude: float, damping: float
) -> Array[float]:
	var first: Array[float] = []
	for layer in 3:
		var age := 0.0
		var found := INF
		while age <= 4.0:
			var offset := WaterRipple.layer_offset_at(
				layer, age, world_x, record.x, span, speed, reach, record.w, amplitude, damping
			)
			if absf(offset) >= VISIBLE_OFFSET:
				found = age
				break
			age += 0.01
		first.append(found)
	return first


func _span(grid: Node2D) -> Vector2:
	if not grid.has_method("get_ripple_span"):
		return Vector2.ZERO
	return grid.call("get_ripple_span", 0) as Vector2


func _reach(grid: Node2D) -> float:
	if not grid.has_method("get_ripple_reach"):
		return 0.0
	return float(grid.call("get_ripple_reach", 0))


## Contiguous columns at one surface level: one water body per entry.
func _find_bodies(grid: Node2D) -> Array[Rect2]:
	var bodies: Array[Rect2] = []
	var room: Rect2 = grid.call("get_room_rect")
	var step := float(grid.get("cell_pixels"))
	var current := Rect2()
	for column in int(room.size.x / step):
		var world_x := room.position.x + (float(column) + 0.5) * step
		var surface := float(grid.call("get_surface_y_at", world_x))
		if surface == INF:
			if current.size.x > 0.0:
				bodies.append(current)
				current = Rect2()
			continue
		if current.size.x > 0.0 and absf(surface - current.position.y) > BODY_LEVEL_TOLERANCE:
			bodies.append(current)
			current = Rect2()
		if current.size.x <= 0.0:
			current = Rect2(world_x, surface, step, 1.0)
		else:
			current.size.x = world_x + step - current.position.x
	if current.size.x > 0.0:
		bodies.append(current)
	return bodies


func _cleanup(grid: Node, runtime: Node, terrain: Node) -> void:
	# Free immediately: a queued-free grid stays in the "water_field" group until the
	# end of the frame, and the next test would resolve it as the active field.
	grid.free()
	runtime.free()
	terrain.free()
