extends Node

## Demo: the water hall focused on fluid simulation (gas disabled).
##
## Two pools, the gate opening, the overflow falling as simulated water streams,
## the hero floating/swimming and the entry splashes that scale with impact
## speed. The Atmosphere node is switched off so only water is shown.

const RUNNER := preload("res://scenes/levels/test/test_world_runner.tscn")


func _ready() -> void:
	var runner := RUNNER.instantiate()
	add_child(runner)
	await get_tree().process_frame
	var world_root := runner.get_node("SubViewportContainer/SubViewport/WorldRoot")
	var atmosphere := world_root.get_node_or_null("Atmosphere")
	if atmosphere != null:
		atmosphere.call("set_enabled", false)
		print("water demo: gas disabled")
