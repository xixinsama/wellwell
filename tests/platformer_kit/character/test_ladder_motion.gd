extends Node

const COMPONENT_PATH := "res://addons/platformer_kit/character/ladder/ladder_motion_component_2d.gd"
const CONTEXT := preload("res://addons/platformer_kit/character/motor/movement_context.gd")
const INTENT := preload("res://addons/platformer_kit/character/input/character_intent.gd")
const PROFILE := preload("res://addons/platformer_kit/character/resources/movement_profile.gd")
const ZONE_SCENE_PATH := "res://addons/platformer_kit/world/entities/ladder_zone.tscn"


func run() -> Array[String]:
	var failures: Array[String] = []
	var script := load(COMPONENT_PATH) as Script
	if script == null:
		return ["ladder motion component is missing"]
	var component := script.new() as Node2D
	var body := CharacterBody2D.new()
	var body_shape := CollisionShape2D.new()
	body_shape.name = "CollisionShape2D"
	body_shape.position = Vector2(0, -3)
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(6, 6)
	body_shape.shape = rectangle
	body.add_child(body_shape)
	add_child(body)
	body.add_child(component)
	var events: Array = []
	component.connect("climb_animation_requested", func(active: bool, direction: Vector2) -> void: events.append([active, direction]))
	var context: RefCounted = CONTEXT.new()
	var intent: RefCounted = INTENT.new()
	var profile: RefCounted = PROFILE.new()
	context.velocity = Vector2(15, 100)
	if not bool(component.call("apply_motion", context, intent, profile, 0.1, true, false)) or context.velocity != Vector2.ZERO:
		failures.append("neutral ladder contact must hover")
	intent.move_axis = 1.0
	component.call("apply_motion", context, intent, profile, 0.1, true, false)
	if context.velocity != Vector2(72, 0):
		failures.append("horizontal climb speed is wrong")
	intent.move_axis = 0.0
	intent.vertical_axis = -1.0
	component.call("apply_motion", context, intent, profile, 0.1, true, false)
	if context.velocity != Vector2(0, -72) or events.back() != [true, Vector2(0, -1)]:
		failures.append("W must climb upward and emit climb animation")
	intent.vertical_axis = 1.0
	component.call("apply_motion", context, intent, profile, 0.1, true, false)
	if context.velocity != Vector2(0, 72) or events.back() != [true, Vector2(0, 1)]:
		failures.append("S alone must climb downward, not drop")
	intent.vertical_axis = -1.0
	intent.move_axis = 1.0
	component.call("apply_motion", context, intent, profile, 0.1, true, false)
	if not is_equal_approx(context.velocity.length(), 72.0):
		failures.append("diagonal climbing must be normalized")
	intent.move_axis = 0.0
	intent.vertical_axis = 0.0
	intent.jump_pressed = true
	intent.jump_held = true
	component.call("apply_motion", context, intent, profile, 0.1, true, false)
	if context.velocity.y != -120.0 or not bool(context.just_jumped):
		failures.append("ladder jump did not use profile jump_speed")
	intent.jump_pressed = false
	context.velocity.y = -100.0
	component.call("apply_motion", context, intent, profile, 0.1, true, false)
	if not is_equal_approx(context.velocity.y, -10.0):
		failures.append("held ladder jump must apply ordinary upward gravity")
	intent.jump_pressed = true
	component.call("apply_motion", context, intent, profile, 0.1, true, false)
	if context.velocity.y != -120.0:
		failures.append("repeated ladder jump was rejected")
	intent.jump_pressed = false
	intent.vertical_axis = 1.0
	intent.jump_pressed = true
	component.call("apply_motion", context, intent, profile, 0.1, true, false)
	if context.velocity.y != 0.0 or not bool(intent.fast_fall) or bool(component.call("apply_motion", context, intent, profile, 0.1, true, false)):
		failures.append("S+Jump must hand control to fast-fall Motor")
	intent.vertical_axis = 0.0
	intent.fast_fall = false
	component.call("apply_motion", context, intent, profile, 0.1, true, false)
	if not bool(intent.fast_fall):
		failures.append("drop latch must persist after button release")
	component.call("apply_motion", context, intent, profile, 0.1, true, true)
	intent.vertical_axis = -1.0
	component.call("apply_motion", context, intent, profile, 0.1, true, false)
	if context.velocity != Vector2(0, -72):
		failures.append("W must clear drop latch and resume climbing")
	intent.vertical_axis = 0.0
	if bool(component.call("apply_motion", context, intent, profile, 0.1, false, false)):
		failures.append("leaving the ladder must return control to ordinary Motor")
	_assert_zone_and_detector(component, failures)
	_assert_player_composition(failures)
	body.free()
	return failures


func _assert_zone_and_detector(component: Node2D, failures: Array[String]) -> void:
	var packed := load(ZONE_SCENE_PATH) as PackedScene
	if packed == null:
		failures.append("reusable ladder zone scene is missing")
		return
	var zone := packed.instantiate() as Area2D
	add_child(zone)
	var detector := component.get_node_or_null("Detector") as Area2D
	if detector == null:
		failures.append("ladder detector was not composed from player shape")
		zone.free()
		return
	detector.area_entered.emit(zone)
	if not bool(component.call("is_on_ladder")):
		failures.append("valid ladder zone was not detected")
	var ordinary := Area2D.new()
	add_child(ordinary)
	detector.area_entered.emit(ordinary)
	if ordinary.is_in_group("ladder_zone"):
		failures.append("ordinary Area2D was mislabeled as a ladder")
	detector.area_exited.emit(zone)
	if bool(component.call("is_on_ladder")):
		failures.append("leaving the ladder zone was not tracked")
	zone.free()
	ordinary.free()


func _assert_player_composition(failures: Array[String]) -> void:
	var packed := load("res://scenes/player/player.tscn") as PackedScene
	var player := packed.instantiate() as CharacterBody2D
	add_child(player)
	player.set_physics_process(false)
	if player.get_node_or_null("LadderMotion") == null:
		failures.append("player scene is missing LadderMotion")
	if not player.has_method("is_on_ladder") or not player.has_signal("climb_animation_requested"):
		failures.append("player climb animation interface is missing")
	var motion := player.get_node_or_null("LadderMotion")
	if motion != null:
		var zone := (load(ZONE_SCENE_PATH) as PackedScene).instantiate() as Area2D
		add_child(zone)
		(motion.get_node("Detector") as Area2D).area_entered.emit(zone)
		if not bool(player.call("is_on_ladder")):
			failures.append("player did not delegate ladder overlap state")
		player.call("respawn_at", Vector2(100, 100))
		if bool(player.call("is_on_ladder")):
			failures.append("respawn retained stale ladder overlap outside the ladder")
		motion.call("refresh_overlaps", [])
		if bool(player.call("is_on_ladder")):
			failures.append("refresh did not clear out-of-ladder contacts")
		motion.call("refresh_overlaps", [zone])
		if not bool(player.call("is_on_ladder")):
			failures.append("refresh did not reacquire an overlapping ladder")
		zone.free()
	player.free()
