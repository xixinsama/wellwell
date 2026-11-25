class_name DustField
extends Node2D

## Slow drifting dust motes in the room's foreground.
##
## The motes are single design pixels, not a texture: `_draw()` stamps one 1x1 rect
## per mote, so they stay exactly one pixel at the 320x180 design resolution and
## never blur or shimmer with the camera. Positions are fully procedural (a seeded
## generator per room), so a room always gets the same dust, tests can assert where
## it is, and there is no particle node, no texture and no allocation per frame.
##
## The field lives in the room rectangle and wraps at its edges, so dust keeps
## drifting for as long as the room is loaded without ever running out. It is drawn
## below the light passes (`z_index` in the scene), which means the room's own
## darkness swallows dust in unlit corners and the lantern's light lifts it back —
## the same rule every other pixel obeys.

const GROUP := &"dust_field"
const CHUNK_PIXELS := Vector2i(320, 180)
## Redraws per second. A mote moves well under a pixel per frame and the twinkle is
## a slow pulse, so quantising the clock here is free visually and saves most of the
## draw cost.
const REDRAW_HZ := 8.0

## Motes in a whole room. A screen is 320x180 px, so 40 is already a visible
## murmur without turning into snow.
@export_range(0, 200, 1) var count := 56
## Base motion in pixels per second. Y is negative because dust rises more often
## than it falls in still air.
@export var drift := Vector2(4.5, -1.6)
## Amplitude of the per-mote sway, in pixels.
@export_range(0.0, 12.0, 0.1) var sway_px := 2.4
## Sway cycles per second.
@export_range(0.0, 2.0, 0.01) var sway_speed := 0.28
## Size of one mote in pixels. 1 keeps it a single pixel; 2 makes it a fleck.
@export_range(1, 3, 1) var pixel_size := 1
@export var dust_color := Color(1.0, 1.0, 1.0)
## Peak opacity of a mote.
@export_range(0.0, 1.0, 0.01) var alpha := 0.62
## How much a mote dims and brightens while drifting, 0 = steady.
@export_range(0.0, 1.0, 0.01) var twinkle := 0.35
## Seed of the per-room layout: same room, same dust.
@export var spawn_seed := 8123
## Dust is drawn above the light passes, so it is not dimmed twice: it reads its
## own brightness from the nearest light instead. This is the share of the peak
## opacity a mote keeps in complete darkness, so the field never disappears.
@export_range(0.0, 1.0, 0.01) var unlit_alpha := 0.35
## Radius of the hero's lantern used for the dust falloff, in pixels.
@export_range(0.0, 260.0, 1.0) var lantern_radius := 90.0
## Authored lights that make the dust glow (same groups the shadow and the light
## field read).
const LIGHT_GROUPS: Array[StringName] = [&"room_light", &"fog_light"]

var _room_rect := Rect2()
var _room_pixels := Vector2i.ZERO
var _room_bound := false
var _enabled := true
var _time := 0.0
var _redraw_step := -1
var _player: Node2D
var _motes := PackedVector2Array()
var _phases := PackedFloat32Array()
var _speeds := PackedFloat32Array()
var _twinkle_speeds := PackedFloat32Array()


func _ready() -> void:
	add_to_group(GROUP)
	# Optional in the scene: registering with the parent world session is the
	# switch, exactly like NormalField and BackdropShadow.
	var world := get_parent()
	if world != null and world.has_method("register_room_extension"):
		world.call("register_room_extension", self)


func bind_player(player: Node2D) -> void:
	_player = player


func bind_room(room_data: Variant, terrain_root: Node, origin_chunk: Variant = null) -> bool:
	return bind_room_with_origin(
		room_data, terrain_root, Vector2i(origin_chunk) if origin_chunk != null else Vector2i.ZERO
	)


## WorldSession room extension entry point. Dust needs nothing but the room
## rectangle, so a room without terrain still gets its motes.
func bind_room_with_origin(room_data: Variant, _terrain_root: Node, origin_chunk: Vector2i) -> bool:
	if room_data == null:
		return false
	var chunks: Vector2i = Vector2i.ONE
	var sizes: Variant = room_data.get("room_size_chunks")
	if sizes != null:
		chunks = Vector2i(sizes)
	if chunks.x <= 0 or chunks.y <= 0:
		chunks = Vector2i.ONE
	var cell_rect := RoomGrid.get_room_cell_rect(origin_chunk, chunks)
	_room_pixels = cell_rect.size * RoomGrid.DEFAULT_CELL_SIZE
	_room_rect = Rect2(
		Vector2(cell_rect.position * RoomGrid.DEFAULT_CELL_SIZE),
		Vector2(_room_pixels)
	)
	_room_bound = true
	_time = 0.0
	_seed_motes()
	queue_redraw()
	return true


func clear_room() -> void:
	_room_bound = false
	_room_rect = Rect2()
	_room_pixels = Vector2i.ZERO
	_motes.clear()
	_phases.clear()
	_speeds.clear()
	_twinkle_speeds.clear()
	queue_redraw()


func set_enabled(value: bool) -> void:
	_enabled = bool(value)
	set_process(_enabled)
	queue_redraw()


func is_enabled() -> bool:
	return _enabled


func get_mote_count() -> int:
	if not _room_bound:
		return 0
	return mini(maxi(count, 0), _motes.size())


func get_room_rect() -> Rect2:
	return _room_rect


## Current mote positions in world space, floored to whole pixels like the draw
## pass stamps them. Tests use this instead of peeking at the draw list.
func get_mote_positions() -> PackedVector2Array:
	var result := PackedVector2Array()
	for index: int in get_mote_count():
		result.append(_mote_position(index))
	return result


func _process(delta: float) -> void:
	if not _room_bound:
		return
	_time += maxf(delta, 0.0)
	# A mote is one pixel and drifts at a few px/s, so most frames would redraw the
	# exact same picture. Quantise the animation clock and only repaint when the
	# quantised time moved: the cost drops from one draw per frame to ~8 per second
	# without any visible difference at this pixel scale.
	var step := int(_time * REDRAW_HZ)
	if step == _redraw_step:
		return
	_redraw_step = step
	queue_redraw()


func _draw() -> void:
	if not _room_bound or not _enabled:
		return
	# One light scan per frame for the whole field, not one per mote.
	var lights := _collect_lights()
	for index: int in get_mote_count():
		var world_position := _mote_position(index)
		var draw_position := world_position - global_position
		var twinkle_speed := _twinkle_speeds[index]
		var pulse := 0.5 + 0.5 * sin(_phases[index] + _time * twinkle_speed)
		var brightness := 1.0 - twinkle * pulse * 0.8
		var lit := _light_factor(lights, world_position)
		draw_rect(
			Rect2(draw_position, Vector2(float(pixel_size), float(pixel_size))),
			Color(dust_color, clampf(alpha * brightness * lit, 0.0, 1.0))
		)


## How much light reaches a mote, 0..1. The dust is stamped above the light passes,
## so it reads the room's light itself: authored lights first, then the hero's
## lantern, and a dark floor so the field never switches off entirely.
func light_factor_at(world_position: Vector2) -> float:
	return _light_factor(_collect_lights(), world_position)


func _collect_lights() -> Array[Dictionary]:
	var lights: Array[Dictionary] = []
	for group: StringName in LIGHT_GROUPS:
		for node: Node in get_tree().get_nodes_in_group(group):
			if not is_instance_valid(node) or not node is Node2D:
				continue
			var radius := float(node.get("radius")) if "radius" in node else lantern_radius
			if radius <= 0.0:
				continue
			lights.append({"position": (node as Node2D).global_position, "radius": radius})
	if is_instance_valid(_player):
		lights.append({"position": _player.global_position, "radius": maxf(lantern_radius, 1.0)})
	return lights


func _light_factor(lights: Array[Dictionary], world_position: Vector2) -> float:
	var best := 0.0
	for light: Dictionary in lights:
		var distance := (light["position"] as Vector2).distance_to(world_position)
		best = maxf(best, clampf(1.0 - distance / float(light["radius"]), 0.0, 1.0))
	return lerpf(unlit_alpha, 1.0, best)


## Position of one mote at the current time: base point, drift, sway, wrapped into
## the room rectangle so a mote that leaves one edge enters the other.
func _mote_position(index: int) -> Vector2:
	var base := _motes[index]
	var phase := _phases[index]
	var speed := _speeds[index]
	var travel := drift * (speed * _time)
	var sway := Vector2(
		sin(_time * sway_speed + phase) * sway_px,
		cos(_time * sway_speed * 0.77 + phase * 1.3) * sway_px * 0.6
	)
	var point := base + travel + sway
	point.x = _room_rect.position.x + fposmod(
		point.x - _room_rect.position.x, maxf(_room_rect.size.x, 1.0)
	)
	point.y = _room_rect.position.y + fposmod(
		point.y - _room_rect.position.y, maxf(_room_rect.size.y, 1.0)
	)
	return point.floor()


func _seed_motes() -> void:
	var total := maxi(count, 0)
	_motes.resize(total)
	_phases.resize(total)
	_speeds.resize(total)
	_twinkle_speeds.resize(total)
	var rng := RandomNumberGenerator.new()
	rng.seed = spawn_seed
	for index: int in total:
		_motes[index] = Vector2(
			_room_rect.position.x + rng.randf() * _room_rect.size.x,
			_room_rect.position.y + rng.randf() * _room_rect.size.y
		)
		_phases[index] = rng.randf() * TAU
		# Motions differ per mote, so the field never reads as one sheet sliding.
		_speeds[index] = 0.55 + rng.randf() * 0.9
		_twinkle_speeds[index] = 0.6 + rng.randf() * 1.6
