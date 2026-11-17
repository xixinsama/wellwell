extends Node

## Regression test for the visible ripple of a settled water body.
##
## A landing never displaces the simulated body: the wobble is drawn by
## `water_grid.gdshader` from three ripple slots, which is the only thing that moves
## the surface of a pool at rest. That ripple used to have a hard-coded
## `exp(-distance / (18 + 22 * w))` envelope plus a +-25 px Gaussian around the wave
## front, so it fell below one rendered pixel about 40 px from the impact.
##
## The lab has a water body that shows the bug clearly: the big pool overflows its rim
## and the water runs down onto the floor, filling a puddle about 220 px wide. A
## landing at the spawn point (x = 24) wobbled columns x = 8..56 and left x = 56..228
## pixel-identical - a hard vertical edge inside one and the same pool, which is what
## "the water on the LEFT side shows ripples, on the RIGHT side flat" describes. It is
## not a scene problem and not a grid-coverage problem: the ripple itself was too
## narrow.
##
## The ripple reach is now measured from the simulation (the width of the surface the
## impact landed in), so a landing carries across the body it belongs to. This test
## pins that contract on the real room, headless: no rendering, no pixels.

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
## Landing speed of a hero jumping into water, px/s. It is what the player component
## reports on a water entry.
const IMPACT_SPEED := 300.0
## A ripple that lifts the surface by less than one rendered pixel is invisible, which
## is exactly the "flat half of the pool" this test guards against.
const MIN_VISIBLE_OFFSET := 1.0
## Surfaces further apart than this are different water bodies.
const BODY_LEVEL_TOLERANCE := 6.0


func run() -> Array[String]:
	var failures: Array[String] = []
	_assert_ripple_spans_the_body(failures)
	return failures


## The floor puddle of the lab, not the pool above it: that is the body the report is
## about (the water that runs down onto the floor).
func _assert_ripple_spans_the_body(failures: Array[String]) -> void:
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
	if bodies.size() < 2:
		failures.append(
			"the lab should hold two water bodies after settling, found %d" % bodies.size()
		)
		_cleanup(grid, runtime, terrain)
		return
	var body := bodies[0]
	for candidate: Rect2 in bodies:
		if candidate.position.y > body.position.y:
			body = candidate
	if body.size.x < 120.0:
		failures.append("the floor puddle is only %.0f px wide, the lab changed" % body.size.x)

	var impact_x := body.position.x + 2.0
	var surface := float(grid.call("get_surface_y_at", impact_x))
	if surface == INF:
		failures.append("the floor puddle has no surface at its left edge")
		_cleanup(grid, runtime, terrain)
		return
	grid.call("request_splash_at", Vector2(impact_x, surface + 1.0), IMPACT_SPEED)

	var reach := _ripple_reach(grid)
	var far_distance := body.end.x - impact_x
	if reach <= 0.0:
		failures.append("a landing reported no ripple reach")
	elif reach < far_distance * 0.9:
		failures.append(
			"the ripple reach %.0f px does not span the %.0f px body it landed in" %
			[reach, body.size.x]
		)
	if reach > body.size.x + 2.0 * float(grid.get("cell_pixels")):
		failures.append(
			"the ripple reach %.0f px escaped its %.0f px body" % [reach, body.size.x]
		)

	# The amplitude has to survive to the far side of the body: sub-pixel is invisible,
	# and an invisible ripple in half of a pool is the seam this test exists to prevent.
	var strength := _ripple_strength(grid)
	var amplitude := float(grid.get("ripple_amplitude"))
	var far_offset := exp(-far_distance / maxf(reach, 1.0)) * strength * amplitude
	if far_offset < MIN_VISIBLE_OFFSET:
		failures.append(
			"the ripple lifts the far side of the body by only %.2f px (reach %.1f px, %.0f px away)" %
			[far_offset, reach, far_distance]
		)
	_cleanup(grid, runtime, terrain)


## Contiguous columns at one surface level: one water body per entry, top to bottom.
## The lab's pool and the puddle under it are two entries.
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
		if current.size.x <= 0.0:
			current = Rect2(world_x, surface, step, 1.0)
		elif absf(surface - current.position.y) <= BODY_LEVEL_TOLERANCE:
			current.size.x = world_x + step - current.position.x
		else:
			bodies.append(current)
			current = Rect2(world_x, surface, step, 1.0)
	if current.size.x > 0.0:
		bodies.append(current)
	return bodies


## Reach of the newest ripple. Looked up by name so this test can be read against an
## older runtime that has no reach at all: that run reports 0 and fails on the
## assertions instead of failing to compile.
func _ripple_reach(grid: Node2D) -> float:
	if not grid.has_method("get_ripple_reach"):
		return 0.0
	var value: Variant = grid.call("get_ripple_reach", 0)
	return 0.0 if value == null else float(value)


func _ripple_strength(grid: Node2D) -> float:
	var ripples: Variant = grid.get("_ripples")
	if ripples is Array and not (ripples as Array).is_empty():
		return ((ripples as Array)[0] as Vector4).w
	return 0.0


func _cleanup(grid: Node, runtime: Node, terrain: Node) -> void:
	# Free immediately: a queued-free grid stays in the "water_field" group until the
	# end of the frame, and the next test would resolve it as the active field.
	grid.free()
	runtime.free()
	terrain.free()
