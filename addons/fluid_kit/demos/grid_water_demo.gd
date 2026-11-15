extends Node

## Demo: the 2D grid fluid room, with the gas switched off.
##
## A tall FluidRegion sits on a raised basin. The top rows start above the dam
## crest, so the fluid pours over the dam, falls onto the right floor and drains
## through the hole. The rock column inside the region shows the other rule: a
## wall inside the region takes its own volume away.

const RUNNER := preload("res://scenes/levels/test/water_grid_runner.tscn")


func _ready() -> void:
	var runner := RUNNER.instantiate()
	add_child(runner)
	await get_tree().process_frame
	var world_root := runner.get_node("SubViewportContainer/SubViewport/WorldRoot")
	var atmosphere := world_root.get_node_or_null("Atmosphere")
	if atmosphere != null:
		atmosphere.call("set_enabled", false)
		print("grid water demo: gas disabled")
	var grid := world_root.get_node_or_null("WaterGrid")
	if grid != null and bool(grid.call("is_ready")):
		print("grid water demo: ", grid.call("get_debug_state"))
