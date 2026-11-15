extends Node

## Development harness for the fluid showcase screenshots.
##
## Starts a runner scene, lets the room settle, then captures the viewport at 4x.
## Water mode also drops the hero into the pool and captures the splash and the
## floating pose; gas mode walks the hero along the floor instead.
##
##   godot --path . --quit-after 600 res://tools/water_capture.tscn
##   godot --path . --quit-after 600 res://tools/gas_capture.tscn

@export var runner_scene: PackedScene = preload("res://scenes/levels/test/test_world_runner.tscn")
@export var output_prefix := "water-hall"
@export var capture_water_drop := true

const OUTPUT_DIR := "res://docs/design"
const SETTLE_SECONDS := 3.2


func _ready() -> void:
	# Watchdog: never leave a stray game window behind if a step throws.
	get_tree().create_timer(25.0).timeout.connect(func() -> void:
		printerr("capture watchdog fired")
		get_tree().quit(1)
	)
	var runner := runner_scene.instantiate()
	add_child(runner)
	_capture(runner)


func _capture(runner: Node) -> void:
	await get_tree().create_timer(SETTLE_SECONDS).timeout
	var world_root := runner.get_node("SubViewportContainer/SubViewport/WorldRoot")
	var viewport := runner.get_node("SubViewportContainer/SubViewport") as SubViewport
	var water := world_root.get_node_or_null("WaterField")
	var atmosphere := world_root.get_node_or_null("Atmosphere")
	var player := world_root.get_node_or_null("Player") as Node2D
	if water != null:
		print("water: %s" % str(water.call("get_debug_state")))
	if atmosphere != null:
		print("atmosphere: %s" % str(atmosphere.call("get_debug_state")))
	await RenderingServer.frame_post_draw
	_save(viewport, _path(""))
	if player == null:
		get_tree().quit(0)
		return
	if capture_water_drop:
		await _capture_water(player, world_root, viewport)
	else:
		await _capture_walk(player, viewport)
	get_tree().quit(0)


## Walks the hero so the gas wake is visible, then lets go.
func _capture_walk(player: Node2D, viewport: SubViewport) -> void:
	Input.action_press(&"move_right")
	await get_tree().create_timer(1.4).timeout
	await RenderingServer.frame_post_draw
	_save(viewport, _path("-walk"))
	Input.action_release(&"move_right")


func _capture_water(player: Node2D, world_root: Node, viewport: SubViewport) -> void:
	Input.action_press(&"move_right")
	await get_tree().create_timer(1.1).timeout
	await RenderingServer.frame_post_draw
	_save(viewport, _path("-wake"))
	Input.action_release(&"move_right")
	await get_tree().create_timer(0.2).timeout

	player.global_position = Vector2(70.0, 246.0)
	if player is CharacterBody2D:
		(player as CharacterBody2D).velocity = Vector2(0.0, 260.0)
	await get_tree().create_timer(0.42).timeout
	await RenderingServer.frame_post_draw
	_save(viewport, _path("-splash"))
	await get_tree().create_timer(2.6).timeout
	await RenderingServer.frame_post_draw
	_save(viewport, _path("-float"))
	var motion := player.get_node_or_null("WaterMotion")
	if motion != null:
		print("hero motion: %s" % str(motion.call("get_debug_state")))


func _path(suffix: String) -> String:
	return "%s/%s%s.png" % [OUTPUT_DIR, output_prefix, suffix]


func _save(viewport: SubViewport, path: String) -> void:
	var image := viewport.get_texture().get_image()
	if image == null or image.get_width() == 0:
		printerr("no viewport image for %s" % path)
		return
	image.resize(image.get_width() * 4, image.get_height() * 4, Image.INTERPOLATE_NEAREST)
	image.save_png(path)
	print("saved %s" % path)
