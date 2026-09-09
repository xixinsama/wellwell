extends Node

const MANIFEST_PATH := "res://addons/platformer_debug/plugin.cfg"
const PLUGIN_PATH := "res://addons/platformer_debug/platformer_debug_plugin.gd"
const HUD_PATH := "res://addons/platformer_debug/runtime/debug_hud.gd"
const VISUALIZER_PATH := "res://addons/platformer_debug/runtime/debug_visualizer_2d.gd"
const DEBUG_MAP_PATH := "res://addons/platformer_debug/runtime/debug_map.gd"
const GRID_OVERLAY_PATH := "res://addons/platformer_debug/runtime/grid_overlay.gd"
const TUNING_HOTKEYS_PATH := "res://addons/platformer_debug/runtime/tuning_hotkeys.gd"
const HUD_SCENE_PATH := "res://addons/platformer_debug/runtime/debug_hud.tscn"
const DEBUG_MAP_SCENE_PATH := "res://addons/platformer_debug/runtime/debug_map.tscn"
const GRID_OVERLAY_SCENE_PATH := "res://addons/platformer_debug/runtime/grid_overlay.tscn"
const OVERLAY_PATH := "res://examples/movement_lab/debug_overlay.tscn"
const DEBUG_LAB_PATH := "res://examples/movement_lab/movement_lab_debug.tscn"
const MOVEMENT_LAB_PATH := "res://examples/movement_lab/movement_lab.tscn"


class DebugSubject extends Node:
	var state := {
		"velocity": Vector2(12.0, -4.0),
		"relative_velocity": Vector2(12.0, -4.0),
		"platform_velocity": Vector2(56.0, 0.0),
		"world_velocity": Vector2(68.0, -4.0),
		"platform_id": &"lab:conveyor",
		"on_floor": true,
		"wall_left": true,
		"wall_right": false,
		"ceiling": false,
		"jump_buffer_remaining": 0.05,
		"coyote_remaining": 0.02,
	}

	func get_debug_state() -> Dictionary:
		return state.duplicate(true)

	func get_persistent_id() -> StringName:
		return &"player:debug:subject"


func run() -> Array[String]:
	var failures: Array[String] = []
	_assert_addon_contract(failures)
	_assert_read_only_debug_binding(failures)
	_assert_optional_example_boundary(failures)
	return failures


func _assert_addon_contract(failures: Array[String]) -> void:
	var config := ConfigFile.new()
	if config.load(MANIFEST_PATH) != OK:
		failures.append("platformer_debug manifest could not be loaded")
	elif String(config.get_value("plugin", "script", "")) != "platformer_debug_plugin.gd":
		failures.append("platformer_debug manifest has the wrong plugin script")
	for path: String in [
		PLUGIN_PATH,
		HUD_PATH,
		VISUALIZER_PATH,
		DEBUG_MAP_PATH,
		GRID_OVERLAY_PATH,
		TUNING_HOTKEYS_PATH,
	]:
		var script := load(path) as Script
		if script == null or not script.can_instantiate():
			failures.append("platformer_debug script could not be loaded: %s" % path)
	for path: String in [HUD_SCENE_PATH, DEBUG_MAP_SCENE_PATH, GRID_OVERLAY_SCENE_PATH]:
		if load(path) as PackedScene == null:
			failures.append("platformer_debug scene could not be loaded: %s" % path)
	var hud_scene := load(HUD_SCENE_PATH) as PackedScene
	if hud_scene != null:
		var hud_instance := hud_scene.instantiate()
		if hud_instance.find_child("DebugPanel", true, false) == null:
			failures.append("debug HUD scene has no compact panel container")
		hud_instance.free()


func _assert_read_only_debug_binding(failures: Array[String]) -> void:
	var hud_script := load(HUD_PATH) as Script
	var visualizer_script := load(VISUALIZER_PATH) as Script
	if hud_script == null or visualizer_script == null:
		return
	var subject := DebugSubject.new()
	var original_state := subject.state.duplicate(true)
	var hud: Control = hud_script.new()
	var label := Label.new()
	label.name = "Label"
	hud.add_child(label)
	hud.bind_subject(subject)
	for section: StringName in [&"motor", &"sensors", &"collision", &"identity"]:
		if not hud.set_section_enabled(section, true):
			failures.append("debug HUD rejected section: %s" % section)
	hud.refresh_display()
	if not label.text.contains("relative 12.0, -4.0") or not label.text.contains("platform 56.0, 0.0"):
		failures.append("debug HUD did not distinguish relative and platform velocity")
	if not label.text.contains("world 68.0, -4.0") or not label.text.contains("lab:conveyor"):
		failures.append("debug HUD did not render world velocity and platform identity")
	if not label.text.contains("wall L true"):
		failures.append("debug HUD did not render motor and sensor state")
	if not label.text.contains("player:debug:subject"):
		failures.append("debug HUD did not render stable identity")
	if subject.state != original_state:
		failures.append("debug HUD mutated its bound gameplay subject")
	var visualizer: Node2D = visualizer_script.new()
	visualizer.bind_subject(subject)
	if not visualizer.has_method("get_velocity_vectors"):
		failures.append("debug visualizer does not expose velocity vectors")
	else:
		var vectors: Dictionary = visualizer.call("get_velocity_vectors")
		if vectors.get("relative") != Vector2(12.0, -4.0) or vectors.get("platform") != Vector2(56.0, 0.0) or vectors.get("world") != Vector2(68.0, -4.0):
			failures.append("debug visualizer lost one or more velocity channels")
	if not visualizer.set_layer_enabled(&"collision", false):
		failures.append("debug visualizer rejected collision toggle")
	if visualizer.is_layer_enabled(&"collision"):
		failures.append("debug visualizer did not retain collision toggle")
	visualizer.free()
	hud.free()
	subject.free()


func _assert_optional_example_boundary(failures: Array[String]) -> void:
	var overlay := load(OVERLAY_PATH) as PackedScene
	if overlay == null:
		failures.append("movement_lab debug overlay could not be loaded independently")
	var debug_lab := load(DEBUG_LAB_PATH) as PackedScene
	if debug_lab == null:
		failures.append("debug-enabled movement_lab could not be loaded")
	var lab_source := FileAccess.get_file_as_string(MOVEMENT_LAB_PATH)
	if lab_source.contains("platformer_debug"):
		failures.append("base movement_lab has a hard dependency on platformer_debug")
