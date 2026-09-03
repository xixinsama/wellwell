extends Node


func run() -> Array[String]:
	var failures: Array[String] = []
	var packed: PackedScene = load("res://scenes/game.tscn") as PackedScene
	if packed == null:
		failures.append("game scene did not load")
		return failures

	var world := packed.instantiate()
	if world.get_node_or_null("Level/BackTiles") == null:
		failures.append("BackTiles missing")
	if world.get_node_or_null("Level/SolidTiles") == null:
		failures.append("SolidTiles missing")
	if world.get_node_or_null("Level/DetailTiles") == null:
		failures.append("DetailTiles missing")
	if world.get_node_or_null("FogOfWar") == null:
		failures.append("FogOfWar missing")
	world.free()
	return failures
