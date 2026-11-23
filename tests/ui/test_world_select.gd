extends Node

const SCENE_PATH := "res://scenes/ui/world_select.tscn"
const CATALOG_PATH := "res://resources/worlds/world_catalog.tres"


func run() -> Array[String]:
	var failures: Array[String] = []
	_assert_catalog(failures)
	_assert_selection_ui(failures)
	_assert_empty_catalog(failures)
	return failures


func _assert_catalog(failures: Array[String]) -> void:
	var catalog := load(CATALOG_PATH) as WorldCatalog
	if catalog == null:
		failures.append("world catalog resource is missing")
		return
	var worlds := catalog.get_worlds()
	if worlds.is_empty():
		failures.append("world catalog exposes no worlds")
		return
	var ids: Array[String] = []
	for world: WorldData in worlds:
		if world.display_name.is_empty():
			failures.append("world catalog entries need display names: %s" % world.world_id)
		if ids.has(world.world_id):
			failures.append("world catalog repeats a world: %s" % world.world_id)
		ids.append(world.world_id)
	# The catalog is authored and grows with the project, so only the reference
	# worlds are required; the count and any later entries are up to the author.
	for required: String in ["the_world", "main_world", "test_world", "loop_world"]:
		if not ids.has(required):
			failures.append("world catalog dropped the reference world: %s" % required)


func _assert_selection_ui(failures: Array[String]) -> void:
	var packed := load(SCENE_PATH) as PackedScene
	if packed == null:
		failures.append("world selection scene is missing")
		return
	var catalog := load(CATALOG_PATH) as WorldCatalog
	var expected_rows := 0 if catalog == null else catalog.get_worlds().size()
	var ui := packed.instantiate() as Control
	add_child(ui)
	ui.call("open_select", "main_world")
	var list := ui.find_child("WorldList", true, false) as VBoxContainer
	if list == null:
		failures.append("world selection list is missing")
		ui.queue_free()
		return
	var rows := list.find_children("WorldRow_*", "HBoxContainer", true, false)
	if rows.size() != expected_rows:
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


## A missing or unloadable catalog must fall back to the empty state instead of
## dying inside the typed-array assignment.
func _assert_empty_catalog(failures: Array[String]) -> void:
	var packed := load(SCENE_PATH) as PackedScene
	if packed == null:
		return
	var ui := packed.instantiate() as Control
	ui.set("catalog", null)
	add_child(ui)
	ui.call("open_select")
	var list := ui.find_child("WorldList", true, false) as VBoxContainer
	if list == null:
		failures.append("world selection list is missing without a catalog")
	else:
		var children := list.get_children()
		if children.size() != 1 or not (children[0] is Label):
			failures.append("world selection did not show its empty state without a catalog")
	ui.queue_free()
