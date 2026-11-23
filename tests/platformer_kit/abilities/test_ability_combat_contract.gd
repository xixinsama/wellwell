extends Node

## The ability and combat modules ship inside Platformer Kit, so they must exist
## there and the base movement lab must stay free of them.

const ABILITY_RUNTIME := "res://addons/platformer_kit/abilities/runtime/ability_runtime.gd"
const ABILITY_CONTROLLER := "res://addons/platformer_kit/abilities/runtime/ability_controller.gd"
const COMBAT_HEALTH := "res://addons/platformer_kit/combat/health_component.gd"
const COMBAT_HITBOX := "res://addons/platformer_kit/combat/hitbox.gd"
const ABILITY_LAB := "res://examples/ability_lab/ability_lab.tscn"
const COMBAT_LAB := "res://examples/combat_lab/combat_lab.tscn"
const MOVEMENT_LAB := "res://examples/movement_lab/movement_lab.tscn"


func run() -> Array[String]:
	var failures: Array[String] = []
	for path: String in [ABILITY_RUNTIME, ABILITY_CONTROLLER, COMBAT_HEALTH, COMBAT_HITBOX]:
		if not FileAccess.file_exists(path):
			failures.append("merged kit module script is missing: %s" % path)
	for path: String in [ABILITY_LAB, COMBAT_LAB]:
		if load(path) as PackedScene == null:
			failures.append("module lab is missing: %s" % path)
	var movement_source := FileAccess.get_file_as_string(MOVEMENT_LAB)
	if movement_source.contains("platformer_kit/abilities/") or movement_source.contains("platformer_kit/combat/"):
		failures.append("base movement lab depends on an optional kit module")
	return failures
