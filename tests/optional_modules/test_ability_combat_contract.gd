extends Node

const ABILITY_MANIFEST := "res://addons/platformer_abilities/plugin.cfg"
const COMBAT_MANIFEST := "res://addons/platformer_combat/plugin.cfg"
const ABILITY_LAB := "res://examples/ability_lab/ability_lab.tscn"
const COMBAT_LAB := "res://examples/combat_lab/combat_lab.tscn"
const MOVEMENT_LAB := "res://examples/movement_lab/movement_lab.tscn"


func run() -> Array[String]:
	var failures: Array[String] = []
	for path: String in [ABILITY_MANIFEST, COMBAT_MANIFEST]:
		var config := ConfigFile.new()
		if config.load(path) != OK:
			failures.append("optional module manifest is missing: %s" % path)
	for path: String in [ABILITY_LAB, COMBAT_LAB]:
		if load(path) as PackedScene == null:
			failures.append("optional module lab is missing: %s" % path)
	var movement_source := FileAccess.get_file_as_string(MOVEMENT_LAB)
	if movement_source.contains("platformer_abilities") or movement_source.contains("platformer_combat"):
		failures.append("base movement lab depends on an optional gameplay module")
	return failures
