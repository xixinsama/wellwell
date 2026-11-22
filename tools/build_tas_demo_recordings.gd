extends SceneTree

## Builds the two deterministic TAS clips used by examples/tas_demo.
## Run headlessly:
##   godot --headless --path . -s res://tools/build_tas_demo_recordings.gd

const DASH := preload("res://addons/platformer_abilities/abilities/dash/default_dash.tres")
const TAS_INPUT := preload("res://addons/platformer_debug/runtime/tas_input_source.gd")
const CHARACTER_INTENT := preload("res://addons/platformer_kit/character/input/character_intent.gd")
const START := Vector2(40.0, 300.0)
const FRAME_COUNT := 360
const SETTLE_FRAMES := 24

var _player: CharacterBody2D
var _tas: RefCounted
var _policy: RefCounted
var _frame := 0
var _phase := 0
var _recording_started := false
var _record_frames := 0


class DemoPolicy:
	extends RefCounted
	var player: Node
	var vertical := 0.0

	func get_intent() -> RefCounted:
		var intent: RefCounted = (load("res://addons/platformer_kit/character/input/character_intent.gd") as Script).new()
		intent.set("move_axis", 1.0)
		intent.set("vertical_axis", vertical)
		if player == null or not player.has_method("get_debug_state"):
			return intent
		var state: Dictionary = player.call("get_debug_state")
		var motion_state := int(state.get("state", 0))
		var attack := float(state.get("dash_attack_remaining", 0.0))
		if motion_state == 0 and bool(state.get("on_floor", false)):
			intent.call("press_action", &"dash")
		elif motion_state == 1 and attack > 0.0:
			intent.set("jump_pressed", true)
			intent.set("jump_held", true)
		return intent


func _initialize() -> void:
	var floor_body := StaticBody2D.new()
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(8000.0, 16.0)
	shape.shape = rect
	shape.position = Vector2(0.0, 308.0)
	floor_body.add_child(shape)
	root.add_child(floor_body)

	_player = (load("res://scenes/player/player.tscn") as PackedScene).instantiate() as CharacterBody2D
	_player.position = START
	_player.set_physics_process(false)
	root.add_child(_player)
	_player.set_physics_process(false)
	_policy = DemoPolicy.new()
	_policy.player = _player
	_tas = TAS_INPUT.new(_policy)
	_player.call("set_input_source", _tas)
	physics_frame.connect(_on_physics_frame)


func _on_physics_frame() -> void:
	_player.set_physics_process(false)
	_frame += 1
	var freeze := root.get_node_or_null("GameFreeze")
	if freeze != null:
		freeze.call("release")
	if _frame == 3:
		_player.call("grant_ability_definition", DASH)
		_reset_player()
		return
	if _frame < 3:
		return
	if not _recording_started:
		if _frame < SETTLE_FRAMES + 3:
			_step_player()
			return
		_tas.call("start_recording")
		_recording_started = true
		return
	_step_player()
	_record_frames += 1
	if freeze != null:
		freeze.call("release")
	if _record_frames < FRAME_COUNT:
		return
	_tas.call("stop_recording")
	_save_current()
	_phase += 1
	if _phase == 1:
		_policy.vertical = 1.0
		_reset_player()
		_tas.call("start_recording")
		_recording_started = true
		_record_frames = 0
		return
	print("TAS demo recordings written")
	quit()


func _reset_player() -> void:
	_player.call("respawn_at", START)
	_player.velocity = Vector2.ZERO


func _step_player() -> void:
	_player.call("_physics_process", 1.0 / 120.0)


func _save_current() -> void:
	var file_name := "super_run.json" if _phase == 0 else "hyper_run.json"
	var path := "res://examples/tas_demo/%s" % file_name
	var payload := {
		"version": 1,
		"physics_ticks": 120,
		"start": [START.x, START.y],
		"frames": _tas.call("get_frames"),
	}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://examples/tas_demo"))
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("cannot write %s" % path)
		return
	file.store_string(JSON.stringify(payload))
	print("wrote ", path, " frames=", _tas.call("get_frame_count"))
