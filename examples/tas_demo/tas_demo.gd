extends Node2D

## Deterministic demo used to record the TAS acceleration test. Two recorded
## input clips are replayed on a flat floor: a super-dash chain and a hyper-dash
## chain. The on-screen HUD reports horizontal speed and the maximum reached.

const TAS_INPUT := preload("res://addons/platformer_debug/runtime/tas_input_source.gd")
const SUPER_PATH := "res://examples/tas_demo/super_run.json"
const HYPER_PATH := "res://examples/tas_demo/hyper_run.json"
const START := Vector2(40.0, 300.0)

@onready var player: CharacterBody2D = $Player
@onready var camera: Camera2D = $Camera2D
@onready var status_label: Label = $Hud/Status
@onready var speed_label: Label = $Hud/Panel/Speed
@onready var title_label: Label = $Hud/Title

var _tas: RefCounted
var _super_frames: Array[Dictionary] = []
var _hyper_frames: Array[Dictionary] = []
var _phase := 0
var _timer := 0.0
var _max_speed := 0.0
var _previous_momentum := false


func _ready() -> void:
	var settings := get_node_or_null("/root/GlobalSettings")
	if settings != null and settings.has_method("set_celeste_momentum_enabled"):
		_previous_momentum = bool(settings.call("is_celeste_momentum_enabled"))
		settings.call("set_celeste_momentum_enabled", true)
	_super_frames = _load_frames(SUPER_PATH)
	_hyper_frames = _load_frames(HYPER_PATH)
	_tas = TAS_INPUT.new(null)
	player.call("set_input_source", _tas)
	player.call("respawn_at", START)
	title_label.text = "Celeste Momentum ON — TAS dash-jump loop"
	status_label.text = "SUPER CHAIN"
	_phase = 0
	_timer = 1.2
	queue_redraw()


func _exit_tree() -> void:
	var settings := get_node_or_null("/root/GlobalSettings")
	if settings != null and settings.has_method("set_celeste_momentum_enabled"):
		settings.call("set_celeste_momentum_enabled", _previous_momentum)


func _physics_process(delta: float) -> void:
	camera.global_position = Vector2(player.global_position.x + 80.0, 210.0)
	var debug: Dictionary = player.call("get_debug_state")
	var world: Vector2 = debug.get("world_velocity", Vector2.ZERO)
	_max_speed = maxf(_max_speed, absf(world.x))
	_update_hud(absf(world.x), debug)
	_timer -= delta
	match _phase:
		0:
			if _timer <= 0.0:
				_start_run(_super_frames, "SUPER CHAIN")
		1:
			if not bool(_tas.call("is_playing")):
				print("TAS super max horizontal speed: %.1f" % _max_speed)
				_phase = 2
				_timer = 1.0
				title_label.text = "super max horizontal speed: %.0f" % _max_speed
		2:
			if _timer <= 0.0:
				_start_run(_hyper_frames, "HYPER / WAVEDASH CHAIN")
		3:
			if not bool(_tas.call("is_playing")):
				print("TAS hyper max horizontal speed: %.1f" % _max_speed)
				_phase = 4
				_timer = 2.0
				title_label.text = "hyper max horizontal speed: %.0f" % _max_speed
		4:
			if _timer <= 0.0:
				get_tree().quit()


func _start_run(frames: Array[Dictionary], label: String) -> void:
	if frames.is_empty():
		title_label.text = "missing TAS recording: %s" % label
		_phase = 4
		_timer = 2.0
		return
	_tas.call("stop")
	_tas.call("set_frames", frames)
	player.call("respawn_at", START)
	_max_speed = 0.0
	_tas.call("start_playback")
	status_label.text = label
	_phase += 1


func _update_hud(speed: float, _debug: Dictionary) -> void:
	if speed_label != null:
		speed_label.text = "vx %5.1f    max %5.1f    frame %d / %d" % [
			speed,
			_max_speed,
			int(_tas.call("get_play_index")),
			int(_tas.call("get_frame_count")),
		]
	if status_label != null:
		status_label.text = status_label.text


func _load_frames(path: String) -> Array[Dictionary]:
	var frames: Array[Dictionary] = []
	if not FileAccess.file_exists(path):
		return frames
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		return frames
	var raw: Variant = (parsed as Dictionary).get("frames", [])
	if not (raw is Array):
		return frames
	var limit := mini((raw as Array).size(), 360)
	for index: int in range(limit):
		var entry: Variant = raw[index]
		if entry is Dictionary:
			frames.append(entry as Dictionary)
	return frames


func _draw() -> void:
	# Distance ticks make the camera scroll readable at a glance.
	for x: int in range(-200, 8200, 40):
		var major := x % 160 == 0
		draw_line(
			Vector2(float(x), 294.0),
			Vector2(float(x), 302.0),
			Color(0.24, 0.34, 0.38, 0.65) if major else Color(0.16, 0.23, 0.26, 0.5),
			1.0 if major else 0.5
		)
