extends Node

func run() -> Array[String]:
	var failures: Array[String] = []
	for path: String in [
		"res://scenes/ui/main_menu.tscn",
		"res://scenes/ui/save_slots.tscn",
		"res://scenes/ui/settings.tscn",
	]:
		if not ResourceLoader.exists(path, "PackedScene"):
			failures.append("missing UI scene: %s" % path)
	return failures

