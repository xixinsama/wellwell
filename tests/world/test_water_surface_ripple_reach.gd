extends Node

## Regression test for the visible ripple of a settled basin (the 1D `WaterField`).
##
## A landing never displaces a basin: the wobble is drawn by `water_surface.gdshader`
## from three ripple slots, and that is the only thing that moves the surface of a
## basin at rest. The shader used to have a hard-coded `exp(-distance / (18 + 22 * w))`
## envelope plus a +-25 px Gaussian around the wave front, so the swell fell below one
## rendered pixel about 40 px from the impact. The water cascade has the widest body of
## the basin rooms: 26 columns of 8 px (208 px) of one level surface. A landing at one
## end of it wobbled about 50 px and left the rest of the very same basin
## pixel-identical - the same "one end ripples, the rest stays flat" seam the grid
## renderer had.
##
## The ripple reach is now measured from the simulation (the width of the surface the
## impact landed in), so a landing carries across the body it belongs to. This test
## pins that contract on the real room, headless: no rendering, no pixels.

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
## Landing speed of a hero jumping into water, px/s. It is what the player component
## reports on a water entry.
const IMPACT_SPEED := 300.0
## A ripple that lifts the surface by less than one rendered pixel is invisible, which
## is exactly the "flat half of the basin" this test guards against.
const MIN_VISIBLE_OFFSET := 1.0
## Surfaces further apart than this are different water bodies.
const BODY_LEVEL_TOLERANCE := 16.0
## The widest body of this room, so a regression in the room data is caught here.
const WIDEST_BODY_MINIMUM := 150.0


func run() -> Array[String]:
	var failures: Array[String] = []
	_assert_ripple_spans_the_body(failures)
	return failures


## The long lower basin of the cascade, which is the widest water body of the baked
## basin rooms.
func _assert_ripple_spans_the_body(failures: Array[String]) -> void:
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
	if body.size.x < WIDEST_BODY_MINIMUM:
		failures.append(
			"the widest cascade body is only %.0f px, the room changed" % body.size.x
		)

	var column_width := float(WATER_FIELD.COLUMN_WIDTH)
	var impact_x := body.position.x + column_width * 0.5
	var surface := float(field.call("get_surface_y_at", impact_x))
	if surface == INF:
		failures.append("the widest body has no surface at its left edge")
		_cleanup(field, runtime, terrain)
		return
	field.call("request_splash", impact_x, IMPACT_SPEED)

	var reach := _ripple_reach(field)
	var far_distance := body.end.x - impact_x
	if reach <= 0.0:
		failures.append("a landing reported no ripple reach")
	elif reach < far_distance * 0.9:
		failures.append(
			"the ripple reach %.0f px does not span the %.0f px body it landed in" %
			[reach, body.size.x]
		)
	if reach > body.size.x + 2.0 * column_width:
		failures.append(
			"the ripple reach %.0f px escaped its %.0f px body" % [reach, body.size.x]
		)

	# The amplitude has to survive to the far side of the body: sub-pixel is invisible,
	# and an invisible ripple in half of a basin is the seam this test exists to prevent.
	var strength := _ripple_strength(field)
	var amplitude := float(WATER_FIELD.RIPPLE_AMPLITUDE)
	var far_offset := exp(-far_distance / maxf(reach, 1.0)) * strength * amplitude
	if far_offset < MIN_VISIBLE_OFFSET:
		failures.append(
			"the ripple lifts the far side of the body by only %.2f px (reach %.1f px, %.0f px away)" %
			[far_offset, reach, far_distance]
		)
	_cleanup(field, runtime, terrain)


## Contiguous wet columns at one surface level: one water body per entry, top to
## bottom. The cascade's upper pool and its long lower basin are two entries.
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
		if current.size.x <= 0.0:
			current = Rect2(world_x, surface, cell, 1.0)
		elif absf(surface - current.position.y) <= BODY_LEVEL_TOLERANCE:
			current.size.x = world_x + cell - current.position.x
		else:
			bodies.append(current)
			current = Rect2(world_x, surface, cell, 1.0)
	if current.size.x > 0.0:
		bodies.append(current)
	return bodies


## Reach of the newest ripple. Looked up by name so this test can be read against an
## older runtime that has no reach at all: that run reports 0 and fails on the
## assertions instead of failing to compile.
func _ripple_reach(field: Node2D) -> float:
	if not field.has_method("get_ripple_reach"):
		return 0.0
	var value: Variant = field.call("get_ripple_reach", 0)
	return 0.0 if value == null else float(value)


func _ripple_strength(field: Node2D) -> float:
	var ripples: Variant = field.get("_ripples")
	if ripples is Array and not (ripples as Array).is_empty():
		return ((ripples as Array)[0] as Vector4).w
	return 0.0


func _cleanup(field: Node, runtime: Node, terrain: Node) -> void:
	# Free immediately: a queued-free field stays in the "water_field" group until the
	# end of the frame, and the next test would resolve it as the active field.
	field.free()
	runtime.free()
	terrain.free()
