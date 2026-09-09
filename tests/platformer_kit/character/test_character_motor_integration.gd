extends Node

const PLAYER_SCENE_PATH := "res://scenes/player/player.tscn"


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
