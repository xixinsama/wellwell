extends Node

const DRIVER_PATH := "res://game/player/hero_animation_controller.gd"
const FRAMES_PATH := "res://resources/player/hero_sprite_frames.tres"
const ROWS := [
	["idle", 0, 2, 2.0, true], ["walk", 1, 4, 8.0, true],
	["run", 2, 4, 12.0, true], ["jump", 3, 2, 10.0, false],
	["fall", 4, 2, 6.0, true], ["climb", 5, 2, 8.0, true],
	["look_up", 6, 1, 1.0, false], ["look_down", 7, 1, 1.0, false],
	["look_left", 8, 1, 1.0, false], ["look_right", 9, 1, 1.0, false],
]


func run() -> Array[String]:
	var failures: Array[String] = []
	var frames := load(FRAMES_PATH) as SpriteFrames
	if frames == null:
		return ["Hero SpriteFrames resource is missing"]
	_assert_frames(frames, failures)
	var driver := _make_driver(frames)
	if driver == null:
		failures.append("Hero animation driver is missing")
		return failures
	var state := _state(true, Vector2.ZERO)
	state.vertical_axis = -1.0
	driver.call("update_visual", 0.0, state)
	if driver.call("get_current_animation") != "look_up":
		failures.append("ground W did not select look_up")
	state.vertical_axis = 1.0
	driver.call("update_visual", 0.0, state)
	if driver.call("get_current_animation") != "look_down":
		failures.append("ground S did not select look_down")
	state = _state(true, Vector2(-20, 0), -1)
	driver.call("update_visual", 0.0, state)
	if driver.call("get_current_animation") != "walk" or not bool(driver.get_node("AnimatedSprite2D").flip_h):
		failures.append("walk speed or generic left flip is wrong")
	state.velocity.x = -90.0
	driver.call("update_visual", 0.0, state)
	if driver.call("get_current_animation") != "run":
		failures.append("run threshold did not select run")
	state = _state(false, Vector2(0, -10), 1)
	driver.call("update_visual", 0.0, state)
	if driver.call("get_current_animation") != "jump":
		failures.append("upward airborne velocity did not select jump")
	state.velocity.y = 10.0
	driver.call("update_visual", 0.0, state)
	if driver.call("get_current_animation") != "fall":
		failures.append("downward airborne velocity did not select fall")
	state = _state(true, Vector2.ZERO, 1)
	driver.call("update_visual", 1.99, state)
	if driver.call("get_current_animation") != "look_right":
		failures.append("idle breathing started before two seconds")
	driver.call("update_visual", 0.02, state)
	if driver.call("get_current_animation") != "idle":
		failures.append("two-second idle breathing did not start")
	state.facing = -1
	driver.call("reset")
	driver.call("update_visual", 0.0, state)
	if driver.call("get_current_animation") != "look_left" or bool(driver.get_node("AnimatedSprite2D").flip_h):
		failures.append("dedicated look_left was incorrectly flipped")
	driver.call("set_climb_state", true, Vector2(0, -1))
	state = _state(false, Vector2(0, -10), 1)
	driver.call("update_visual", 0.0, state)
	if driver.call("get_current_animation") != "climb":
		failures.append("W climb did not take priority over jump")
	driver.call("set_climb_state", true, Vector2(0, 1))
	state.velocity.y = 50.0
	driver.call("update_visual", 0.0, state)
	if driver.call("get_current_animation") != "climb":
		failures.append("S climb did not take priority over fall")
	driver.call("set_climb_state", true, Vector2.ZERO)
	state.velocity = Vector2.ZERO
	driver.call("update_visual", 2.1, state)
	if driver.call("get_current_animation") != "idle":
		failures.append("neutral ladder contact incorrectly selected fall or blocked idle")
	driver.call("set_climb_state", false, Vector2.ZERO)
	state.velocity.y = -100.0
	state.just_jumped = true
	driver.call("update_visual", 0.0, state)
	var sprite := driver.get_node("AnimatedSprite2D") as AnimatedSprite2D
	sprite.frame = 1
	driver.call("update_visual", 0.0, state)
	if driver.call("get_current_animation") != "jump" or sprite.frame != 0:
		failures.append("repeated jump did not restart the jump animation")
	driver.call("reset")
	if driver.call("get_current_animation") != "" or float(driver.get("_idle_elapsed")) != 0.0:
		failures.append("Hero reset retained stale animation state")
	driver.free()
	_assert_player_scene(failures)
	return failures


func _state(grounded: bool, velocity: Vector2, facing: int = 1) -> Dictionary:
	return {
		"grounded": grounded, "velocity": velocity, "move_axis": 0.0,
		"vertical_axis": 0.0, "facing": facing, "just_jumped": false,
	}


func _make_driver(frames: SpriteFrames) -> Node2D:
	var script := load(DRIVER_PATH) as Script
	if script == null:
		return null
	var driver := script.new() as Node2D
	var sprite := AnimatedSprite2D.new()
	sprite.name = "AnimatedSprite2D"
	sprite.sprite_frames = frames
	driver.add_child(sprite)
	add_child(driver)
	return driver


func _assert_frames(frames: SpriteFrames, failures: Array[String]) -> void:
	for row: Array in ROWS:
		var animation := StringName(row[0])
		if not frames.has_animation(animation):
			failures.append("missing Hero animation: %s" % animation)
			continue
		if frames.get_frame_count(animation) != int(row[2]):
			failures.append("wrong frame count: %s" % animation)
		if not is_equal_approx(frames.get_animation_speed(animation), float(row[3])):
			failures.append("wrong animation speed: %s" % animation)
		if frames.get_animation_loop(animation) != bool(row[4]):
			failures.append("wrong loop setting: %s" % animation)
		for column: int in range(row[2]):
			var texture := frames.get_frame_texture(animation, column) as AtlasTexture
			if texture == null or texture.region != Rect2(column * 10, row[1] * 10, 10, 10):
				failures.append("wrong atlas region: %s frame %d" % [animation, column])


func _assert_player_scene(failures: Array[String]) -> void:
	var player := (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	for path: String in ["SpriteRoot/Block", "SpriteRoot/MeshInstance2D", "SpriteRoot/MeshInstance2D2"]:
		var placeholder := player.get_node_or_null(path) as CanvasItem
		# A deleted placeholder is as good as a hidden one: only a leftover that
		# is still drawing fails the contract.
		if placeholder != null and placeholder.visible:
			failures.append("old placeholder must be hidden: %s" % path)
	var sprite := player.get_node_or_null("SpriteRoot/HeroAnimation/AnimatedSprite2D") as AnimatedSprite2D
	if sprite == null or sprite.position != Vector2(0, -5):
		failures.append("Hero sprite or feet anchor is missing")
	if player.get_node_or_null("LadderMotion") == null:
		failures.append("player lost LadderMotion during Hero composition")
	player.free()
