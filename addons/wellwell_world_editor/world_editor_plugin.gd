@tool
extends EditorPlugin

const DOCK_SCENE := preload("res://addons/wellwell_world_editor/world_editor_dock.tscn")

var _dock: Control


func _enter_tree() -> void:
	_dock = DOCK_SCENE.instantiate()
	_dock.set_undo_redo_adapter(get_undo_redo())
	_dock.set_editor_interface(get_editor_interface())
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _dock)


func _exit_tree() -> void:
	if _dock != null:
		remove_control_from_docks(_dock)
		_dock.free()
		_dock = null


func _handles(object: Object) -> bool:
	return object is WorldData


func _edit(object: Object) -> void:
	if _dock != null:
		var world := object as WorldData if _handles(object) else null
		_dock.set_world_data(world)
