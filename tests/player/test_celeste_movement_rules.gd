extends Node

const PLAYER_SCENE_PATH := "res://scenes/player/player.tscn"
const PROFILE_PATH := "res://addons/platformer_kit/character/resources/movement_profile.gd"
const INTENT_PATH := "res://addons/platformer_kit/character/input/character_intent.gd"
const DASH_PATH := "res://addons/platformer_abilities/abilities/dash/default_dash.tres"


class StubInput:
	extends RefCounted
	var intent: RefCounted

	func _init(value: RefCounted) -> void:
		intent = value

	func get_intent() -> RefCounted:
		return intent


func run() -> Array[String]:
	var failures: Array[String] = []
	_assert_rule_velocities(failures)
	_assert_dash_state(failures)
	_assert_standalone_dash_install(failures)
	_assert_advanced_jumps(failures)
	_assert_dash_jump_rules(failures)
	_assert_wall_jumps(failures)
	return failures


func _assert_rule_velocities(failures: Array[String]) -> void:
	var profile: RefCounted = (load(PROFILE_PATH) as Script).new()
	if Vector2(PlayerMotionRules.super_jump_velocity(profile, 1, false)) != Vector2(260, -120):
		failures.append("super jump velocity is wrong")
	if Vector2(PlayerMotionRules.super_jump_velocity(profile, 1, true)) != Vector2(325, -60):
		failures.append("hyper jump velocity is wrong")
	if Vector2(PlayerMotionRules.wall_jump_velocity(profile, -1)) != Vector2(-130, -120):
		failures.append("wall jump velocity is wrong")
	if Vector2(PlayerMotionRules.wallbounce_velocity(profile, 1)) != Vector2(170, -160):
		failures.append("wallbounce velocity is wrong")
	if not is_equal_approx(PlayerMotionRules.wall_slide_cap(profile, 1.2), 20.0):
		failures.append("wall slide did not start at its slow cap")
	if not is_equal_approx(PlayerMotionRules.wall_slide_cap(profile, 0.0), 160.0):
		failures.append("wall slide did not reach the normal fall cap")


func _assert_wall_jumps(failures: Array[String]) -> void:
	var packed := load(PLAYER_SCENE_PATH) as PackedScene
	if packed == null:
		return
	var player := packed.instantiate() as CharacterBody2D
	add_child(player)
	player.set_physics_process(false)
	var context: RefCounted = player.call("get_movement_context")
	var intent: RefCounted = (load(INTENT_PATH) as Script).new()
	player.set("_state", PlayerMotionState.State.WALL_GRAB)
	player.set("_wall_direction", 1)
	context.set("dash_attack_remaining", 0.0)
	intent.set("move_axis", -1.0)
	intent.set("jump_pressed", true)
	if not bool(player.call("_try_wall_jump", intent)):
		failures.append("away input did not produce a wall jump")
	elif not Vector2(context.get("velocity")).is_equal_approx(Vector2(-130, -120)):
		failures.append("wall jump velocity is wrong")
	if float(context.get("force_move_x_remaining")) <= 0.0 or float(context.get("wall_grab_lockout")) <= 0.0:
		failures.append("wall jump did not force movement or lock auto-grab")
	player.set("_state", PlayerMotionState.State.WALL_GRAB)
	player.set("_wall_direction", 1)
	player.call("get_stamina").call("refill")
	intent.set("move_axis", 1.0)
	intent.set("vertical_axis", 0.0)
	intent.set("jump_pressed", true)
	if not bool(player.call("_try_wall_jump", intent)):
		failures.append("toward input did not produce a wall jump")
	elif not Vector2(context.get("velocity")).is_equal_approx(Vector2(-130, -120)):
		failures.append("toward-wall jump did not push away")
	if not is_equal_approx(float(player.call("get_stamina").call("get_current")), 110.0):
		failures.append("free wall jump spent stamina")
	player.set("_state", PlayerMotionState.State.WALL_GRAB)
	player.set("_wall_direction", 1)
	player.call("get_stamina").call("refill")
	intent.set("move_axis", 1.0)
	intent.set("vertical_axis", -1.0)
	intent.set("jump_pressed", true)
	if not bool(player.call("_try_wall_jump", intent)):
		failures.append("up input did not produce a climb jump")
	elif not Vector2(context.get("velocity")).is_equal_approx(Vector2(0, -120)):
		failures.append("climb jump velocity is wrong")
	if not is_equal_approx(float(player.call("get_stamina").call("get_current")), 82.5):
		failures.append("climb jump did not spend its stamina")
	intent.set("move_axis", -1.0)
	intent.set("vertical_axis", 0.0)
	player.call("_update_climb_jump_conversion", intent, 1.0 / 60.0)
	if not Vector2(context.get("velocity")).is_equal_approx(Vector2(-130, -120)):
		failures.append("climb jump did not convert to a wall jump")
	if not is_equal_approx(float(player.call("get_stamina").call("get_current")), 110.0):
		failures.append("climb jump conversion did not refund stamina")
	player.free()


func _assert_dash_jump_rules(failures: Array[String]) -> void:
	var packed := load(PLAYER_SCENE_PATH) as PackedScene
	if packed == null:
		return
	var player := packed.instantiate() as CharacterBody2D
	add_child(player)
	player.set_physics_process(false)
	var context: RefCounted = player.call("get_movement_context")
	var environment: RefCounted = player.call("get_environment_snapshot")
	environment.set("grounded", true)
	player.set("_state", PlayerMotionState.State.DASH)
	player.set("_dash_direction", Vector2.RIGHT)
	context.set("dash_attack_remaining", 0.2)
	var intent: RefCounted = (load(INTENT_PATH) as Script).new()
	intent.set("move_axis", 1.0)
	intent.set("jump_pressed", true)
	if not bool(player.call("_try_dash_jump", intent)):
		failures.append("grounded dash jump was rejected")
	elif not Vector2(context.get("velocity")).is_equal_approx(Vector2(260, -120)):
		failures.append("dash jump did not produce super velocity")
	player.set("_state", PlayerMotionState.State.DASH)
	player.set("_dash_direction", Vector2.RIGHT)
	player.set("_ducking", true)
	context.set("dash_attack_remaining", 0.2)
	if not bool(player.call("_try_dash_jump", intent)):
		failures.append("ducking dash jump was rejected")
	elif not Vector2(context.get("velocity")).is_equal_approx(Vector2(325, -60)):
		failures.append("dash jump did not produce hyper velocity")
	player.free()


func _assert_standalone_dash_install(failures: Array[String]) -> void:
	var packed := load(PLAYER_SCENE_PATH) as PackedScene
	if packed == null:
		return
	var player := packed.instantiate() as CharacterBody2D
	add_child(player)
	player.set_physics_process(false)
	var loadout := player.get_node_or_null("AbilityLoadout")
	if loadout == null:
		failures.append("player scene is missing AbilityLoadout")
		player.free()
		return
	loadout.call("_install_unbound_definitions")
	if loadout.call("get_dash_runtime") == null:
		failures.append("standalone player did not auto-install its authored dash")
	player.free()


func _assert_advanced_jumps(failures: Array[String]) -> void:
	var packed := load(PLAYER_SCENE_PATH) as PackedScene
	if packed == null:
		return
	var player := packed.instantiate() as CharacterBody2D
	add_child(player)
	player.set_physics_process(false)
	var context: RefCounted = player.call("get_movement_context")
	var environment: RefCounted = player.call("get_environment_snapshot")
	environment.set("grounded", true)
	context.set("dash_attack_remaining", 0.2)
	context.set("coyote_remaining", 0.1)
	player.set("_dash_direction", Vector2.RIGHT)
	var intent: RefCounted = (load(INTENT_PATH) as Script).new()
	intent.set("move_axis", 1.0)
	intent.set("jump_pressed", true)
	if not bool(player.call("_try_advanced_jump", intent)):
		failures.append("grounded dash jump did not become a super")
	elif not Vector2(context.get("velocity")).is_equal_approx(Vector2(260, -120)):
		failures.append("super jump velocity is wrong in the player state")
	player.set("_ducking", true)
	context.set("velocity", Vector2.ZERO)
	if not bool(player.call("_try_advanced_jump", intent)):
		failures.append("ducking dash jump did not become a hyper")
	elif not Vector2(context.get("velocity")).is_equal_approx(Vector2(325, -60)):
		failures.append("hyper jump velocity is wrong in the player state")
	player.free()


func _assert_dash_state(failures: Array[String]) -> void:
	var packed := load(PLAYER_SCENE_PATH) as PackedScene
	if packed == null:
		failures.append("player scene is missing")
		return
	var player := packed.instantiate() as CharacterBody2D
	add_child(player)
	player.set_physics_process(false)
	player.call("grant_ability_definition", load(DASH_PATH))
	var intent: RefCounted = (load(INTENT_PATH) as Script).new()
	intent.call("press_action", &"dash")
	intent.set("move_axis", 1.0)
	player.call("set_input_source", StubInput.new(intent))
	player.call("_physics_process", 1.0 / 60.0)
	var freeze := get_node_or_null("/root/GameFreeze")
	if freeze != null:
		freeze.call("release")
	if int(player.call("get_motion_state")) != PlayerMotionState.State.DASH:
		failures.append("dash input did not enter the DASH state")
	var debug: Dictionary = player.call("get_debug_state")
	if float(debug.get("dash_attack_remaining", 0.0)) <= 0.0:
		failures.append("dash did not start its attack window")
	if player.velocity.length() > 0.01:
		failures.append("dash moved on its freeze frame")
	player.call("_physics_process", 1.0 / 60.0)
	if not player.velocity.is_equal_approx(Vector2(240.0, 0.0)):
		failures.append("dash did not move at dash speed after freeze")
	player.call("_step_dash", (load(INTENT_PATH) as Script).new(), 0.2)
	if int(player.call("get_motion_state")) != PlayerMotionState.State.NORMAL:
		failures.append("dash did not return to NORMAL when it expired")
	var context: RefCounted = player.call("get_movement_context")
	if not Vector2(context.get("velocity")).is_equal_approx(Vector2(160.0, 0.0)):
		failures.append("dash did not keep its end speed")
	player.free()
