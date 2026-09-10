extends Node

const LAB_SCENE := "res://examples/ability_lab/ability_lab.tscn"
const DEFAULT_DASH := preload("res://addons/platformer_abilities/abilities/dash/default_dash.tres")


func run() -> Array[String]:
	var failures: Array[String] = []
	var packed := load(LAB_SCENE) as PackedScene
	if packed == null:
		return ["Ability Lab scene could not be loaded"]
	var lab := packed.instantiate()
	add_child(lab)
	var player := lab.get_node_or_null("Player")
	var pickup := lab.get_node_or_null("AbilityPickup")
	var ground := lab.get_node_or_null("Ground/CollisionShape2D")
	if player == null or pickup == null or ground == null:
		failures.append("Ability Lab is missing its interactive player, pickup, or ground")
	else:
		if pickup.get("ability_definition") != DEFAULT_DASH:
			failures.append("Ability Lab pickup does not use the reusable default Dash definition")
		if not pickup.call("collect_for", player):
			failures.append("Ability Lab pickup could not grant Dash to the reference player")
		var controller := player.get_node_or_null("AbilityLoadout/AbilityController")
		if controller == null or not controller.call("has_ability", &"dash"):
			failures.append("Ability Lab does not exercise reference player Dash integration")
	var status := lab.get_node_or_null("Status") as Label
	if status == null or status.text == "Ability runtime pending":
		failures.append("Ability Lab did not initialize observable runtime status")
	var source := FileAccess.get_file_as_string("res://examples/ability_lab/ability_lab.gd")
	if source.contains("ABILITY_DEFINITION.new") or source.contains("lab_dash"):
		failures.append("Ability Lab still builds a startup-only synthetic ability")
	lab.free()
	return failures
