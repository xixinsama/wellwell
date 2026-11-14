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
	_assert_component_cadence_and_space(failures)
	_assert_component_direction_and_completion(failures)
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


func _assert_component_cadence_and_space(failures: Array[String]) -> void:
	var script := load("res://game/player/player_motion_effects.gd") as Script
	if script == null:
		failures.append("player motion effects component is missing")
		return
	var actor := Node2D.new()
	add_child(actor)
	actor.global_position = Vector2(12, 18)
	var effects := script.new() as Node2D
	actor.add_child(effects)
	effects.call("update_motion", 0.14, true, 100.0, 1)
	if effects.get_child_count() != 1:
		failures.append("running did not emit one footstep")
	var footstep := effects.get_child(0) as Node2D
	var emitted_at := footstep.global_position
	actor.global_position.x += 30.0
	if footstep.global_position != emitted_at:
		failures.append("footstep followed the actor instead of staying in world space")
	effects.call("update_motion", 0.01, true, 100.0, 1)
	if effects.get_child_count() != 1:
		failures.append("running ignored its emission interval")
	effects.call("play_land")
	var count_after_land := effects.get_child_count()
	effects.call("update_motion", 0.01, true, 100.0, 1)
	if effects.get_child_count() != count_after_land:
		failures.append("landing and running emitted overlapping dust")
	effects.call("update_motion", 0.2, false, 100.0, 1)
	effects.call("update_motion", 0.2, true, 0.0, 1)
	if effects.get_child_count() != count_after_land:
		failures.append("airborne or stationary movement emitted running dust")
	effects.call("clear_effects")
	for child: Node in effects.get_children():
		if not child.is_queued_for_deletion():
			failures.append("clear_effects did not release transient nodes")
	actor.free()


func _assert_component_direction_and_completion(failures: Array[String]) -> void:
	var script := load("res://game/player/player_motion_effects.gd") as Script
	if script == null:
		return
	var effects := script.new() as Node2D
	add_child(effects)
	effects.call("update_motion", 0.14, true, -100.0, -1)
	if effects.get_child_count() != 1 or not bool(effects.get_child(0).get("flip")):
		failures.append("left-running dust was not mirrored")
	effects.call("play_jump")
	effects.call("play_hurt")
	for child: Node in effects.get_children():
		if not bool(child.get("free_when_done")):
			failures.append("one-shot does not free itself")
		child.call("_process", 2.0)
		if not child.is_queued_for_deletion():
			failures.append("finished one-shot was not queued for release")
	effects.free()
