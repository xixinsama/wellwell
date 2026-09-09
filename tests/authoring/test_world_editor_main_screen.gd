extends Node

const PLUGIN := preload("res://addons/world_editor/world_editor_plugin.gd")
const MAIN_SCENE_PATH := "res://addons/world_editor/world_editor_main.tscn"


func run() -> Array[String]:
	var failures: Array[String] = []
	var method_names: Array[StringName] = []
	var plugin_script: Script = PLUGIN
	for method: Dictionary in plugin_script.get_script_method_list():
		method_names.append(method.get("name", &""))
	for required_method: StringName in [
		&"_has_main_screen",
		&"_make_visible",
		&"_get_plugin_name",
		&"_get_plugin_icon",
	]:
		if not method_names.has(required_method):
			failures.append("World Editor plugin is missing main-screen method: %s" % required_method)
	var packed := load(MAIN_SCENE_PATH) as PackedScene
	if packed == null:
		failures.append("World Editor main-screen scene is missing")
	else:
		var state := packed.get_state()
		if state.get_node_type(0) != &"VBoxContainer":
			failures.append("World Editor main-screen scene root is not Control")
		elif (int(_scene_node_property(state, 0, &"size_flags_vertical", 0)) & Control.SIZE_EXPAND) == 0:
			failures.append("World Editor main screen does not expand vertically")
		var layout_canvas_index := _scene_node_index(state, "LayoutCanvas")
		if layout_canvas_index < 0 or not bool(_scene_node_property(state, layout_canvas_index, &"clip_contents", false)):
			failures.append("World Editor canvas does not clip enlarged room previews to its bounds")
	return failures


func _scene_node_index(state: SceneState, path: String) -> int:
	for index: int in state.get_node_count():
		if String(state.get_node_path(index)).trim_prefix("./") == path:
			return index
	return -1


func _scene_node_property(state: SceneState, node_index: int, property: StringName, default: Variant) -> Variant:
	for property_index: int in state.get_node_property_count(node_index):
		if state.get_node_property_name(node_index, property_index) == property:
			return state.get_node_property_value(node_index, property_index)
	return default
