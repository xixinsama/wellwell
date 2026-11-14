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
		var end_instance: RefCounted = Px.createFx(script, {"x": float(meta.origin[0]), "y": float(meta.origin[1])})
		end_instance.update(float(meta.duration))
		frame.clear()
		end_instance.draw(frame)
		if _visible_pixels(frame) != 0:
			failures.append("one-shot is not empty at exact duration: %s" % path)
	_assert_jump_debris(Px, failures)
	_assert_land_spread(Px, failures)
	_assert_hurt_falls(Px, failures)
	_assert_component_cadence_and_space(failures)
	_assert_component_direction_and_completion(failures)
	_assert_player_composition(failures)
	_assert_real_landing_and_lock(failures)
	_assert_controller_event_order(failures)
	return failures


func _visible_pixels(frame: RefCounted) -> int:
	var count := 0
	for color: int in frame.color:
		if color != 0:
			count += 1
	return count


func _assert_jump_debris(Px: RefCounted, failures: Array[String]) -> void:
	var script := load(EFFECT_PATHS[0]) as Script
	if script == null:
		return
	var meta: Dictionary = script.get("meta")
	var instance: RefCounted = Px.createFx(script, {})
	var particles: RefCounted = instance.impl.get("particles")
	var debris_indices: Array[int] = []
	var initial_y: Array[float] = []
	for index: int in range(particles.list.size()):
		var particle: Dictionary = particles.list[index]
		if int(particle.k) == int(Px.P.FLAKE):
			debris_indices.append(index)
			initial_y.append(particle.y)
	if debris_indices.size() != 3:
		failures.append("jump must emit three fading downward flakes")
		return
	instance.update(0.16)
	var bottom: float = float(meta.size[1]) - float(meta.origin[1])
	for index: int in range(debris_indices.size()):
		var particle: Dictionary = particles.list[debris_indices[index]]
		if float(particle.y) <= initial_y[index]:
			failures.append("jump flakes must move downward")
		if float(particle.y) >= bottom - 0.5:
			failures.append("jump flakes leave the canvas before mid-flight")
		if float(particle.life) <= 0.0:
			failures.append("jump flakes must remain alive at mid-flight")


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
		if int(child.get("z_index")) != 1:
			failures.append("effect draw order must stay in front of the player")
		child.call("_process", 2.0)
		if not child.is_queued_for_deletion():
			failures.append("finished one-shot was not queued for release")
	effects.free()


class EffectsRecorder:
	extends Node
	var events: Array[String] = []
	var motion_samples: Array[Dictionary] = []

	func play_jump() -> void:
		events.append("jump")

	func play_land() -> void:
		events.append("land")

	func play_hurt() -> void:
		events.append("hurt:%s" % str((get_parent() as Node2D).global_position))

	func update_motion(_delta: float, _grounded: bool, _speed: float, _facing: int) -> void:
		motion_samples.append({"grounded": _grounded, "speed": _speed})

	func clear_effects() -> void:
		events.append("clear")


class StubInput:
	extends RefCounted
	var intent: RefCounted

	func _init(value: RefCounted) -> void:
		intent = value

	func get_intent() -> RefCounted:
		return intent


func _assert_player_composition(failures: Array[String]) -> void:
	var packed := load("res://scenes/player/player.tscn") as PackedScene
	if packed == null:
		failures.append("player scene is missing")
		return
	var player := packed.instantiate() as CharacterBody2D
	var old_effects := player.get_node_or_null("MotionEffects")
	if old_effects != null:
		player.remove_child(old_effects)
		old_effects.free()
	var recorder := EffectsRecorder.new()
	recorder.name = "MotionEffects"
	player.add_child(recorder)
	add_child(player)
	player.set_physics_process(false)
	if not player.has_method("play_hurt_effect"):
		failures.append("player has no explicit post-respawn hurt-effect entry")
	else:
		player.call("respawn_at", Vector2(68, 140))
		if recorder.events != ["clear"]:
			failures.append("ordinary respawn must clear old effects without hurt: %s" % str(recorder.events))
		player.call("play_hurt_effect")
		if recorder.events.back() != "hurt:%s" % str(Vector2(68, 140)):
			failures.append("hurt effect did not use the post-respawn position: %s" % str(recorder.events))
	if not "_motion_effects" in player:
		failures.append("player controller does not compose MotionEffects")
	else:
		recorder.events.clear()
		var context: RefCounted = player.call("get_movement_context")
		context.set("coyote_remaining", 0.05)
		var intent: RefCounted = load("res://addons/platformer_kit/character/input/character_intent.gd").new()
		intent.set("jump_pressed", true)
		intent.set("jump_held", true)
		player.call("set_input_source", StubInput.new(intent))
		player.call("_physics_process", 1.0 / 60.0)
		if recorder.events.count("jump") != 1:
			failures.append("actual motor jump did not emit exactly one jump effect")
	player.free()


func _assert_real_landing_and_lock(failures: Array[String]) -> void:
	var packed := load("res://scenes/player/player.tscn") as PackedScene
	if packed == null:
		return
	var floor_body := StaticBody2D.new()
	floor_body.position = Vector2(0, 4)
	var floor_shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(128, 8)
	floor_shape.shape = rectangle
	floor_body.add_child(floor_shape)
	add_child(floor_body)
	var player := packed.instantiate() as CharacterBody2D
	var old_effects := player.get_node_or_null("MotionEffects")
	if old_effects != null:
		player.remove_child(old_effects)
		old_effects.free()
	var recorder := EffectsRecorder.new()
	recorder.name = "MotionEffects"
	player.add_child(recorder)
	player.position = Vector2.ZERO
	add_child(player)
	player.set_physics_process(false)
	player.call("set_input_source", StubInput.new(load("res://addons/platformer_kit/character/input/character_intent.gd").new()))
	for index: int in range(2):
		player.call("_physics_process", 1.0 / 60.0)
	if recorder.events.count("land") != 0:
		failures.append("initial or continuous grounding emitted a landing effect")
	player.global_position = Vector2(0, -24)
	player.velocity = Vector2.ZERO
	recorder.events.clear()
	for index: int in range(120):
		player.call("_physics_process", 1.0 / 60.0)
		if recorder.events.count("land") == 1:
			break
	if recorder.events.count("land") != 1:
		failures.append("airborne to grounded did not emit exactly one landing effect")
	for index: int in range(10):
		player.call("_physics_process", 1.0 / 60.0)
	if recorder.events.count("land") != 1:
		failures.append("continuous grounding repeated the landing effect")
	recorder.motion_samples.clear()
	player.call("set_control_locked", true)
	for index: int in range(5):
		player.call("_physics_process", 1.0 / 60.0)
	if not recorder.motion_samples.is_empty():
		failures.append("control-locked player continued running-effect updates")
	player.call("set_control_locked", false)
	recorder.events.clear()
	player.call("respawn_at", Vector2.ZERO)
	recorder.events.clear()
	player.call("_physics_process", 1.0 / 60.0)
	if recorder.events.has("land"):
		failures.append("respawn falsely emitted landing on its first motion sample")
	player.free()
	floor_body.free()


func _assert_controller_event_order(failures: Array[String]) -> void:
	var source := FileAccess.get_file_as_string("res://scripts/player/player_controller.gd")
	var jump_hook := source.find("_movement_context.just_jumped")
	var slide := source.find("move_and_slide()")
	var land_hook := source.find("not was_on_floor and is_on_floor()")
	var run_hook := source.find("\"update_motion\"", slide)
	if jump_hook < 0:
		failures.append("jump effect is not driven by actual just_jumped")
	if slide < 0 or land_hook <= slide or run_hook <= slide:
		failures.append("landing and running hooks must follow move_and_slide")
