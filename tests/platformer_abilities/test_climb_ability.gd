extends Node

const DEFINITION_PATH := "res://addons/platformer_abilities/abilities/climb/climb_ability_definition.gd"
const DEFAULT_CLIMB_PATH := "res://addons/platformer_abilities/abilities/climb/default_climb.tres"
const LOADOUT_PATH := "res://game/player/player_ability_loadout.gd"
const CONTROLLER_PATH := "res://addons/platformer_abilities/runtime/ability_controller.gd"
const PLAYER_SCENE_PATH := "res://scenes/player/player.tscn"
const PICKUP_PATH := "res://addons/platformer_abilities/entities/climb_pickup.tscn"
const PROGRESSION := preload("res://addons/metroidvania_kit/progression/progression_context.gd")


func run() -> Array[String]:
	var failures: Array[String] = []
	if not ResourceLoader.exists(DEFAULT_CLIMB_PATH):
		return ["default Climb ability resource is missing"]
	var definition: Resource = load(DEFAULT_CLIMB_PATH)
	if definition == null or StringName(definition.get("ability_id")) != &"climb":
		failures.append("default Climb ability does not use the climb id")
	_assert_loadout_grant(failures)
	_assert_player_scene_composition(failures)
	_assert_pickup_preset(failures)
	return failures


func _assert_pickup_preset(failures: Array[String]) -> void:
	var packed := load(PICKUP_PATH) as PackedScene
	if packed == null:
		failures.append("Climb pickup preset is missing")
		return
	var pickup := packed.instantiate()
	var definition: Resource = pickup.get("ability_definition")
	if definition == null or StringName(definition.get("ability_id")) != &"climb":
		failures.append("Climb pickup preset does not carry the climb definition")
	pickup.free()


func _assert_loadout_grant(failures: Array[String]) -> void:
	var loadout: Node = (load(LOADOUT_PATH) as Script).new()
	loadout.name = "AbilityLoadout"
	var controller: Node = (load(CONTROLLER_PATH) as Script).new()
	controller.name = "AbilityController"
	loadout.add_child(controller)
	add_child(loadout)
	var definitions: Array[Resource] = [load(DEFAULT_CLIMB_PATH)]
	loadout.set("ability_definitions", definitions)
	if not bool(loadout.call("grant_ability_definition", load(DEFAULT_CLIMB_PATH))):
		failures.append("Climb ability could not be granted through the player loadout")
	if not bool(loadout.call("has_ability", &"climb")):
		failures.append("player loadout did not expose the granted Climb ability")
	if controller.call("get_runtime", &"climb") == null:
		failures.append("Climb ability did not install a runtime entry")
	var progression: RefCounted = PROGRESSION.new()
	loadout.call("bind_progression", progression)
	if bool(loadout.call("has_ability", &"climb")):
		failures.append("empty progression did not lock Climb")
	progression.call("grant_ability", &"climb")
	loadout.call("synchronize_unlocked_abilities")
	if not bool(loadout.call("has_ability", &"climb")):
		failures.append("restored progression did not unlock Climb")
	loadout.free()


func _assert_player_scene_composition(failures: Array[String]) -> void:
	var player := (load(PLAYER_SCENE_PATH) as PackedScene).instantiate() as CharacterBody2D
	var loadout := player.get_node_or_null("AbilityLoadout")
	if loadout == null:
		failures.append("player scene has no AbilityLoadout for Climb")
		player.free()
		return
	var definitions: Array = loadout.get("ability_definitions")
	var found := false
	for definition: Resource in definitions:
		if definition != null and StringName(definition.get("ability_id")) == &"climb":
			found = true
	if not found:
		failures.append("player scene does not author the Climb ability")
	player.free()
