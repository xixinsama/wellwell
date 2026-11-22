extends Node

const SCREEN_SCENE := preload("res://scenes/ui/collection_screen.tscn")


func run() -> Array[String]:
	var failures: Array[String] = []
	var registry := get_node_or_null("/root/Collectibles")
	if registry == null:
		return ["Collectibles autoload is missing"]
	registry.call("reset")
	registry.set("current_world_id", "test_collection_screen")
	registry.call("register_number", 1)
	registry.call("register_number", 2)
	registry.call("register_number", 3)
	registry.call("collect_number", 2)

	var screen := SCREEN_SCENE.instantiate() as Control
	add_child(screen)
	if String(screen.call("get_badge_text")) != "图鉴 1 / 3":
		failures.append("collection badge text is wrong: %s" % screen.call("get_badge_text"))

	screen.call("open")
	if not bool(screen.call("is_open")):
		failures.append("collection screen did not open")
	if not get_tree().paused:
		failures.append("collection screen did not pause the game")

	var grid := screen.find_child("Grid", true, false) as GridContainer
	if grid == null or grid.get_child_count() != 3:
		failures.append("collection grid did not list every number")
	elif not bool(grid.get_child(1).get_meta(&"collected", false)):
		failures.append("the collected number is not marked in the grid")
	elif bool(grid.get_child(0).get_meta(&"collected", true)):
		failures.append("a missing number is marked collected")
	var count_label := screen.find_child("Count", true, false) as Label
	if count_label == null or count_label.text != "1 / 3":
		failures.append("collection count is wrong: %s" % (count_label.text if count_label != null else "<none>"))

	screen.call("close")
	if bool(screen.call("is_open")) or get_tree().paused:
		failures.append("collection screen did not close and unpause cleanly")

	# The rebindable toggle action opens and closes it too.
	var toggle := InputEventAction.new()
	toggle.action = &"collection_toggle"
	toggle.pressed = true
	screen.call("_unhandled_input", toggle)
	if not bool(screen.call("is_open")):
		failures.append("collection_toggle did not open the screen")
	var cancel := InputEventAction.new()
	cancel.action = &"ui_cancel"
	cancel.pressed = true
	screen.call("_unhandled_input", cancel)
	if bool(screen.call("is_open")) or get_tree().paused:
		failures.append("ui_cancel did not close the collection screen")

	registry.call("reset")
	if screen.find_child("Badge", true, false).visible:
		failures.append("collection badge stayed visible without a world")
	screen.queue_free()
	return failures
