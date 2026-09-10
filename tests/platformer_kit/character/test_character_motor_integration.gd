extends Node

const PLAYER_SCENE_PATH := "res://scenes/player/player.tscn"
const DEFAULT_DASH := preload("res://addons/platformer_abilities/abilities/dash/default_dash.tres")
const CHARACTER_INTENT := preload("res://addons/platformer_kit/character/input/character_intent.gd")


func run() -> Array[String]:
	var failures: Array[String] = []
	var packed := load(PLAYER_SCENE_PATH) as PackedScene
	if packed == null:
		return ["player scene could not be loaded for motor integration"]
	var player := packed.instantiate() as CharacterBody2D
	add_child(player)
	if not player.has_method("set_input_source") or not player.has_method("get_movement_context"):
		failures.append("PlayerController does not expose motor composition seams")
	elif player.call("get_movement_context") == null:
		failures.append("PlayerController did not create a MovementContext")
	if not "tuning" in player or player.get("tuning") == null:
		failures.append("PlayerController lost its tuning compatibility property")
	elif not "ground_acceleration" in player.get("tuning"):
		failures.append("PlayerController tuning is not backed by MovementProfile")
	if not player.has_method("get_character_sensors") or not player.has_method("get_environment_snapshot"):
		failures.append("PlayerController does not expose sensor composition seams")
	elif player.call("get_character_sensors") == null or player.call("get_environment_snapshot") == null:
		failures.append("PlayerController did not create its framework sensors")
	var loadout := player.get_node_or_null("AbilityLoadout")
	if loadout == null or loadout.get_node_or_null("AbilityController") == null:
		failures.append("reference player scene is missing its ability composition")
	elif not player.has_method("grant_ability_definition") or not player.call("grant_ability_definition", DEFAULT_DASH):
		failures.append("PlayerController did not delegate ability grants")
	else:
		var dash_intent: RefCounted = CHARACTER_INTENT.new()
		dash_intent.call("press_action", &"dash")
		player.velocity = Vector2(30, 40)
		if not player.call("_apply_ability_motion", dash_intent):
			failures.append("PlayerController did not apply an active Dash override")
		elif not player.velocity.is_equal_approx(Vector2(DEFAULT_DASH.dash_speed, 0)):
			failures.append("PlayerController did not replace motor velocity with Dash velocity")
		loadout.get_node("AbilityController").call("cancel", &"dash")
		player.velocity = Vector2(30, 40)
		if player.call("_apply_ability_motion", CHARACTER_INTENT.new()) or player.velocity != Vector2(30, 40):
			failures.append("PlayerController changed motor velocity while Dash was inactive")
	var player_source := FileAccess.get_file_as_string("res://scripts/player/player_controller.gd")
	var motor_step := player_source.find("_motor.call(\"step\"")
	var ability_step := player_source.find("_apply_ability_motion(intent)")
	var slide_step := player_source.find("move_and_slide()")
	if motor_step < 0 or ability_step <= motor_step or slide_step <= ability_step:
		failures.append("PlayerController does not apply ability motion between Motor and move_and_slide")
	var debug_state: Dictionary = player.call("get_debug_state")
	for key: String in ["relative_velocity", "platform_velocity", "world_velocity"]:
		if not debug_state.has(key) or not debug_state[key] is Vector2:
			failures.append("PlayerController debug state is missing %s" % key)
	if debug_state.get("relative_velocity") != player.velocity:
		failures.append("relative velocity does not match CharacterBody2D velocity")
	if player.has_method("get_movement_context"):
		var context: RefCounted = player.call("get_movement_context")
		if context != null:
			context.set("jump_buffer_remaining", 0.05)
			context.set("coyote_remaining", 0.05)
	player.velocity = Vector2(20.0, 30.0)
	player.call("respawn_at", Vector2(12.0, 18.0))
	if player.global_position != Vector2(12.0, 18.0) or player.velocity != Vector2.ZERO:
		failures.append("PlayerController respawn behavior changed during motor composition")
	if player.has_method("get_movement_context"):
		var context: RefCounted = player.call("get_movement_context")
		if context != null and (float(context.get("jump_buffer_remaining")) > 0.0 or float(context.get("coyote_remaining")) > 0.0):
			failures.append("PlayerController respawn did not reset motor timers")
	player.queue_free()
	return failures
