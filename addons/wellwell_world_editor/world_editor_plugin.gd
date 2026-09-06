@tool
extends EditorPlugin

const MAIN_SCENE := preload("res://addons/wellwell_world_editor/world_editor_main.tscn")

var _main: Control


func _enter_tree() -> void:
	_main = MAIN_SCENE.instantiate() as Control
	_main.set_undo_redo_adapter(get_undo_redo())
	_main.set_editor_interface(get_editor_interface())
	EditorInterface.get_editor_main_screen().add_child(_main)
	_make_visible(false)


func _exit_tree() -> void:
	if is_instance_valid(_main):
		_main.queue_free()
	_main = null


func _has_main_screen() -> bool:
	return true


func _make_visible(visible: bool) -> void:
	if is_instance_valid(_main):
		_main.visible = visible


func _get_plugin_name() -> String:
	return "World"


func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_editor_theme().get_icon("Node2D", "EditorIcons")


func _handles(object: Object) -> bool:
	return object is WorldData


func _edit(object: Object) -> void:
	if _main != null:
		var world := object as WorldData if _handles(object) else null
		_main.set_world_data(world, true)
