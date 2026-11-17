extends Node

const SCENE_PATH := "res://scenes/ui/world_select.tscn"
const CATALOG_PATH := "res://resources/worlds/world_catalog.tres"


func run() -> Array[String]:
	var failures: Array[String] = []
	_assert_catalog(failures)
	_assert_selection_ui(failures)
	return failures


func _assert_catalog(failures: Array[String]) -> void:
	var catalog := load(CATALOG_PATH) as WorldCatalog
	if catalog == null:
		failures.append("world catalog resource is missing")
		return
	var worlds := catalog.get_worlds()
	if worlds.size() != 4:
		failures.append("world catalog must expose the project worlds"
			+ " and the test and loop worlds")
		return
	if (
		worlds[0].world_id != "the_world"
		or worlds[1].world_id != "main_world"
		or worlds[2].world_id != "test_world"
		or worlds[3].world_id != "loop_world"
	):
		failures.append("world catalog order or ids changed")
	for world: WorldData in worlds:
		if world.display_name.is_empty():
			failures.append("world catalog entries need display names")


func _assert_selection_ui(failures: Array[String]) -> void:
	var packed := load(SCENE_PATH) as PackedScene
	if packed == null:
		failures.append("world selection scene is missing")
		return
	var ui := packed.instantiate() as Control
	add_child(ui)
	ui.call("open_select", "main_world")
	var list := ui.find_child("WorldList", true, false) as VBoxContainer
	if list == null:
		failures.append("world selection list is missing")
		ui.queue_free()
		return
	var rows := list.find_children("WorldRow_*", "HBoxContainer", true, false)
	if rows.size() != 4:
		failures.append("world selection did not build one row per world")
		ui.queue_free()
		return
	var chosen: Array[WorldData] = []
	ui.connect("world_chosen", func(world: WorldData) -> void: chosen.append(world))
	var enter := rows[0].find_child("EnterButton", true, false) as Button
	if enter == null:
		failures.append("world row is missing its enter button")
	else:
		enter.pressed.emit()
	if chosen.size() != 1 or chosen[0].world_id != "the_world":
		failures.append("world row did not emit its world")
	if ui.visible:
		failures.append("world selection stayed visible after choosing a world")
	var back_count: Array[int] = [0]
	ui.connect("back_requested", func() -> void: back_count[0] += 1)
	ui.call("_request_back")
	if back_count[0] != 1:
		failures.append("world selection back button did not emit")
	ui.queue_free()
