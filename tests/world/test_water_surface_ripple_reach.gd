extends Node

## Regression test for the shape of the visible ripple on the 1D basin water.
##
## A landing never displaces a basin: the wobble is drawn by
## `water_surface.gdshader` from three ripple slots, and two things about that wave were
## wrong before:
##
##   1. a crest has to *travel*. The old model multiplied a static distance envelope by
##      `cos(distance - speed * age)`, so at small ages every column had nearly the same
##      phase: the whole basin lifted at once and the far end moved before the crest
##      could reach it;
##   2. a crest has to come back off the walls of the basin, and there was no
##      reflection at all.
##
## `WaterField` measures the basin under the impact from the simulation and hands its
## walls and width to the shader, so the test can predict both the arrival time and the
## echo time. It asserts them on the water cascade's long lower basin, the widest body
## of the baked basin rooms (208 px).

const ROOM_DATA := preload("res://resources/rooms/generated/water_cascade.tres")
const RUNTIME_SCENE := preload("res://scenes/rooms/generated/water_cascade/runtime.tscn")
const TERRAIN_SCENE := preload("res://scenes/rooms/generated/water_cascade/terrain.tscn")
const WATER_FIELD := preload("res://addons/fluid_kit/runtime/water/water_field.gd")

## The room is placed in the test world at this chunk, so the baked room content has
## to live at the same world origin the world session uses.
const ORIGIN_CHUNK := Vector2i(0, 2)
const STEP := 1.0 / 120.0
## Frames to let the cascade basins settle.
const SETTLE_STEPS := 1200
## Landing speed of a hero jumping into water, px/s.
const IMPACT_SPEED := 300.0
## A displacement below this is under half a rendered pixel: invisible, so a column
## "has not moved" as far as the player is concerned.
const VISIBLE_OFFSET := 0.5
## Surfaces further apart than this are different water bodies.
const BODY_LEVEL_TOLERANCE := 16.0
## The widest body of this room, so a room edit is caught here.
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
	var origin := Vector2(ORIGIN_CHUNK) * WATER_FIELD.CHUNK_PIXELS
	runtime.position = origin
	terrain.position = origin
	add_child(runtime)
	add_child(terrain)
	var field := WATER_FIELD.new() as Node2D
	add_child(field)
	if not bool(field.call("bind_room_with_origin", ROOM_DATA, terrain, ORIGIN_CHUNK)):
		failures.append("water field refused to bind to the water cascade room")
		_cleanup(field, runtime, terrain)
		return
	for _step: int in SETTLE_STEPS:
		field.call("_physics_process", STEP)

	var bodies := _find_bodies(field)
	if bodies.is_empty():
		failures.append("the water cascade room has no water body after settling")
		_cleanup(field, runtime, terrain)
		return
	var body := bodies[0]
	for candidate: Rect2 in bodies:
		if candidate.size.x > body.size.x:
			body = candidate
	if body.size.x < BODY_MINIMUM:
		failures.append("the widest cascade body is only %.0f px, the room changed" % body.size.x)

	var column_width := float(WATER_FIELD.COLUMN_WIDTH)
	var impact := body.position.x + column_width * 0.5
	var surface := float(field.call("get_surface_y_at", impact))
	if surface == INF:
		failures.append("the widest body has no surface at its left end")
		_cleanup(field, runtime, terrain)
		return
	field.call("request_splash", impact, IMPACT_SPEED)

	var ripples: Array = field.get("_ripples")
	if ripples.is_empty():
		failures.append("a landing recorded no ripple")
		_cleanup(field, runtime, terrain)
		return
	var record: Vector4 = ripples[0]
	var span := _span(field)
	var reach := _reach(field)
	var speed := float(WATER_FIELD.RIPPLE_SPEED)
	var amplitude := float(WATER_FIELD.RIPPLE_AMPLITUDE)
	var damping := float(WATER_FIELD.RIPPLE_DAMPING)

	# The walls are the measured edges of the body the splash landed in.
	if span.x > body.position.x + column_width * 2.0 \
			or span.y < body.end.x - column_width * 2.0:
		failures.append(
			"the ripple walls %.0f..%.0f do not match the %.0f..%.0f body" %
			[span.x, span.y, body.position.x, body.end.x]
		)
	if reach < body.size.x * 0.9:
		failures.append(
			"the ripple reach %.0f px does not span the %.0f px body" % [reach, body.size.x]
		)

	# 1. Arrival order: the crest starts at the impact and reaches the far end later.
	var near_x := impact + column_width
	var far_x := body.end.x - column_width * 0.5
	var near_arrival := WaterRipple.arrival(absf(near_x - impact), speed)
	var far_arrival := WaterRipple.arrival(absf(far_x - impact), speed)
	var early := near_arrival + 0.10
	if absf(_offset(early, near_x, record, span, speed, reach, amplitude, damping)) < VISIBLE_OFFSET:
		failures.append("the column next to the landing had not moved by %.2f s" % early)
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

	# 2. Reflection: the crest that hits the far wall comes back.
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
		failures.append("the layer crests do not arrive back to front: %s" % str(layers))
	if absf(layers[1] - WaterRipple.arrival(direct_distance, speed)) > TIME_TOLERANCE:
		failures.append(
			"the middle layer arrived at %.2f s instead of %.2f s" %
			[layers[1], WaterRipple.arrival(direct_distance, speed)]
		)
	_cleanup(field, runtime, terrain)


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


func _span(field: Node2D) -> Vector2:
	if not field.has_method("get_ripple_span"):
		return Vector2.ZERO
	return field.call("get_ripple_span", 0) as Vector2


func _reach(field: Node2D) -> float:
	if not field.has_method("get_ripple_reach"):
		return 0.0
	return float(field.call("get_ripple_reach", 0))


## Contiguous wet columns at one surface level: one water body per entry.
func _find_bodies(field: Node2D) -> Array[Rect2]:
	var bodies: Array[Rect2] = []
	var cell := float(WATER_FIELD.COLUMN_WIDTH)
	var current := Rect2()
	var index := 0
	while true:
		var column: Dictionary = field.call("get_column_debug", index)
		if column.is_empty():
			break
		index += 1
		var wet := not bool(column.get("blocked", false)) \
				and float(column.get("depth", 0.0)) > 0.02
		if not wet:
			if current.size.x > 0.0:
				bodies.append(current)
				current = Rect2()
			continue
		var surface := float(column.get("surface", 0.0))
		var world_x := float(column.get("x", 0.0))
		if current.size.x > 0.0 and absf(surface - current.position.y) > BODY_LEVEL_TOLERANCE:
			bodies.append(current)
			current = Rect2()
		if current.size.x <= 0.0:
			current = Rect2(world_x, surface, cell, 1.0)
		else:
			current.size.x = world_x + cell - current.position.x
	if current.size.x > 0.0:
		bodies.append(current)
	return bodies


func _cleanup(field: Node, runtime: Node, terrain: Node) -> void:
	# Free immediately: a queued-free field stays in the "water_field" group until the
	# end of the frame, and the next test would resolve it as the active field.
	field.free()
	runtime.free()
	terrain.free()
