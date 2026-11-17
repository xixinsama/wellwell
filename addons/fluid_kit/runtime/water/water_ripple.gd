class_name WaterRipple
extends RefCounted

## The impact-ripple model, in GDScript.
##
## The water shaders draw exactly this curve (`ripple_surface` in
## water_grid.gdshader and in water_surface.gdshader). It lives here as well because a
## shader cannot run in a headless test, and the two things that have to be proven
## about a ripple are the arrival order of its crest and the echo off the walls of the
## body - both are timing, not pixels. The tuning numbers below are defined *only*
## here: WaterGrid and WaterField push them into their material uniforms, so the
## renderer and the tests cannot drift apart.
##
## Shape of one crest: it leaves the impact point and travels at `speed` px/s, so a
## column at `distance` px is exactly at rest until `distance / speed` seconds have
## passed. After that the surface rises once and falls once (one `OMEGA` cycle) while
## the amplitude rings down. That is what makes a splash read as a wave crossing the
## pool instead of the whole body lifting together.
##
## Walls: a body edge (a dry column, a drop, or a different pool level - whatever
## WaterGrid/WaterField measured as the end of the body) sends the crest back. The
## method of images gives that for free: mirroring the impact across each edge is a
## virtual source whose crest reaches a column at
## `(distance_to_the_wall + distance_from_the_wall) / speed`, so the echo needs no
## extra simulation and cannot leak outside the body.

## Angular frequency of one crest passing one column, rad/s. One cycle is about
## 0.84 s, so a landing reads as a single heavy swell.
const OMEGA := 7.5
## Share of the crest that comes back off a body edge.
const REFLECTION := 0.55
## The three surfaces of a water body, back to front. `delay` is how much later that
## surface starts moving (s), `speed` scales how fast its crest travels and
## `amplitude` scales how far it lifts the surface. The front surface arrives first
## and the back one last, so a passing wave shows three crests out of phase instead of
## one flat line.
const LAYERS := [
	{"delay": 0.10, "speed": 0.92, "amplitude": 0.60},
	{"delay": 0.0, "speed": 1.0, "amplitude": 1.0},
	{"delay": -0.06, "speed": 1.12, "amplitude": 0.50},
]
## How far each surface sits from the simulated one, in px (positive = further down,
## i.e. "deeper"): the back crest reads lower and the front crest reads higher, which
## is what gives the body its visible thickness.
const LAYER_OFFSETS := [1.5, 0.0, -1.5]
## Layer indices, so callers do not pass bare integers around.
const LAYER_BACK := 0
const LAYER_MID := 1
const LAYER_FRONT := 2


## Time the crest of a wave travelling at `speed` px/s needs to cover `distance` px.
static func arrival(distance: float, speed: float) -> float:
	return distance / maxf(speed, 1.0)


## Displacement of a surface (px, positive = it rises) at `distance` from one source,
## `age` seconds after the impact. Exactly zero until the crest arrives, then one
## damped rise and fall as it passes.
static func offset_at(
	age: float,
	distance: float,
	speed: float,
	reach: float,
	strength: float,
	amplitude: float,
	damping: float
) -> float:
	var travel := arrival(distance, speed)
	if age <= travel:
		return 0.0
	var local := age - travel
	var lift := sin(local * OMEGA) * exp(-local * maxf(damping, 0.0))
	return lift * exp(-distance / maxf(reach, 1.0)) * strength * amplitude


## Displacement of one surface of a body (px, positive = it rises) at `world_x`, from
## one impact: the direct crest plus its two mirrors across the body edges.
##
## `reflection` is the share of the crest that comes back off an edge. It defaults to
## the model's REFLECTION; passing 0 gives the direct wave alone, which is what lets a
## test separate the echo from the crest that just passed.
static func body_offset_at(
	age: float,
	world_x: float,
	impact_x: float,
	walls: Vector2,
	speed: float,
	reach: float,
	strength: float,
	amplitude: float,
	damping: float,
	reflection: float = REFLECTION
) -> float:
	var total := offset_at(
		age, absf(world_x - impact_x), speed, reach, strength, amplitude, damping
	)
	if reflection <= 0.0:
		return total
	total += reflection * offset_at(
		age, absf(world_x - (2.0 * walls.x - impact_x)), speed, reach, strength, amplitude, damping
	)
	total += reflection * offset_at(
		age, absf(world_x - (2.0 * walls.y - impact_x)), speed, reach, strength, amplitude, damping
	)
	return total


## Same for one of the three visible surfaces of the body.
static func layer_offset_at(
	layer: int,
	age: float,
	world_x: float,
	impact_x: float,
	walls: Vector2,
	speed: float,
	reach: float,
	strength: float,
	amplitude: float,
	damping: float,
	reflection: float = REFLECTION
) -> float:
	var entry: Dictionary = LAYERS[clampi(layer, 0, LAYERS.size() - 1)]
	return body_offset_at(
		age - float(entry["delay"]),
		world_x,
		impact_x,
		walls,
		speed * float(entry["speed"]),
		reach,
		strength,
		amplitude * float(entry["amplitude"]),
		damping,
		reflection
	)


## Pushes the model into a water shader: the crest frequency, the reflection share and
## the three layers. Both renderers call this, so the numbers above are the only place
## they exist and a headless test can reason about exactly what the shader will do.
static func apply_to(material: ShaderMaterial) -> void:
	if material == null:
		return
	material.set_shader_parameter("ripple_omega", OMEGA)
	material.set_shader_parameter("ripple_reflection", REFLECTION)
	var back: Dictionary = LAYERS[LAYER_BACK]
	var front: Dictionary = LAYERS[LAYER_FRONT]
	material.set_shader_parameter("layer_back_delay", float(back["delay"]))
	material.set_shader_parameter("layer_back_speed", float(back["speed"]))
	material.set_shader_parameter("layer_back_amplitude", float(back["amplitude"]))
	material.set_shader_parameter(
		"layer_back_drop", float(LAYER_OFFSETS[LAYER_BACK])
	)
	material.set_shader_parameter("layer_front_delay", float(front["delay"]))
	material.set_shader_parameter("layer_front_speed", float(front["speed"]))
	material.set_shader_parameter("layer_front_amplitude", float(front["amplitude"]))
	material.set_shader_parameter("layer_front_rise", -float(LAYER_OFFSETS[LAYER_FRONT]))


## World y of one layer's crest at `world_x`: the simulated surface, shifted by the
## layer's depth offset and lifted by that layer's own ripple. Positive displacement
## raises the surface, and y grows downward, so the lift is subtracted.
static func layer_crest_y(
	layer: int,
	age: float,
	world_x: float,
	base_surface_y: float,
	impact_x: float,
	walls: Vector2,
	speed: float,
	reach: float,
	strength: float,
	amplitude: float,
	damping: float
) -> float:
	var offset := layer_offset_at(
		layer, age, world_x, impact_x, walls, speed, reach, strength, amplitude, damping
	)
	return base_surface_y + float(LAYER_OFFSETS[clampi(layer, 0, LAYER_OFFSETS.size() - 1)]) - offset
