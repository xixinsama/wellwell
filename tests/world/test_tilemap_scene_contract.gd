extends Node


func run() -> Array[String]:
	var failures: Array[String] = []
	var packed: PackedScene = load("res://scenes/rooms/generated/level_0/terrain.tscn") as PackedScene
	if packed == null:
		failures.append("generated terrain scene did not load")
		return failures

	var world := packed.instantiate()
	if world.get_node_or_null("Terrain/BackTiles") == null:
		failures.append("BackTiles missing")
	if world.get_node_or_null("Terrain/SolidTiles") == null:
		failures.append("SolidTiles missing")
	if world.get_node_or_null("Terrain/DetailTiles") == null:
		failures.append("DetailTiles missing")
	world.free()
	return failures
