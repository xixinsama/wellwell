extends Node

## Demo: the three-pool cascade focused on fluid simulation (gas disabled).
##
## Pool A (high, left) spills into pool B (middle), which spills into pool C
## (low, right): two waterfalls, three basins. The Atmosphere is switched off so
## only water is shown.

const RUNNER := preload("res://scenes/levels/test/water_cascade_runner.tscn")


func _ready() -> void:
	var runner := RUNNER.instantiate()
	add_child(runner)
	await get_tree().process_frame
	var world_root := runner.get_node("SubViewportContainer/SubViewport/WorldRoot")
	var atmosphere := world_root.get_node_or_null("Atmosphere")
	if atmosphere != null:
		atmosphere.call("set_enabled", false)
		print("water demo: gas disabled")
