extends Node

const PX_PATH := "res://addons/pixelfx/core/px.gd"
const EFFECT_PATHS := [
	"res://game/player/effects/jump_dust.gd",
	"res://game/player/effects/run_dust.gd",
	"res://game/player/effects/land_dust.gd",
	"res://game/player/effects/respawn_hurt.gd",
]


func run() -> Array[String]:
	var failures: Array[String] = []
	var Px := load(PX_PATH)
	if Px == null:
		return ["PixelFX core is missing"]
	for path: String in EFFECT_PATHS:
		var script := load(path) as Script
		if script == null:
			failures.append("missing effect: %s" % path)
			continue
		var meta: Dictionary = script.get("meta")
		var instance: RefCounted = Px.createFx(script, {"x": float(meta.origin[0]), "y": float(meta.origin[1])})
		var frame: RefCounted = Px.createFrame(meta.size[0], meta.size[1])
		instance.update(0.08)
		instance.draw(frame)
		if _visible_pixels(frame) == 0:
			failures.append("effect has no visible key frame: %s" % path)
		instance.update(float(meta.duration) + 0.1)
		frame.clear()
		instance.draw(frame)
		if _visible_pixels(frame) != 0:
			failures.append("one-shot does not end empty: %s" % path)
	_assert_land_spread(Px, failures)
	_assert_hurt_falls(Px, failures)
	return failures


func _visible_pixels(frame: RefCounted) -> int:
	var count := 0
	for color: int in frame.color:
		if color != 0:
			count += 1
	return count


func _assert_land_spread(Px: RefCounted, failures: Array[String]) -> void:
	var script := load(EFFECT_PATHS[2]) as Script
	if script == null:
		return
	var instance: RefCounted = Px.createFx(script, {})
	var particles: RefCounted = instance.impl.get("particles")
	var left := false
	var right := false
	for particle: Dictionary in particles.list:
		left = left or float(particle.vx) < 0.0
		right = right or float(particle.vx) > 0.0
	if not left or not right:
		failures.append("landing dust must travel both left and right")


func _assert_hurt_falls(Px: RefCounted, failures: Array[String]) -> void:
	var script := load(EFFECT_PATHS[3]) as Script
	if script == null:
		return
	var instance: RefCounted = Px.createFx(script, {})
	var particles: RefCounted = instance.impl.get("particles")
	var initial_y: Array[float] = []
	for particle: Dictionary in particles.list:
		initial_y.append(particle.y)
	instance.update(0.08)
	for index: int in range(initial_y.size()):
		if float(particles.list[index].y) <= initial_y[index]:
			failures.append("respawn hurt particles must fall downward")
			return
