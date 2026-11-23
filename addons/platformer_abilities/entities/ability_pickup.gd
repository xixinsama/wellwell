class_name AbilityPickup
extends "res://addons/platformer_kit/world/entities/pickup_entity.gd"

const ABILITY_DEFINITION := preload("res://addons/platformer_abilities/runtime/ability_definition.gd")

@export var ability_definition: Resource


func _ready() -> void:
	super()
	entity_type = "ability_pickup"
	var activation_area := get_node_or_null("ActivationArea") as Area2D
	if activation_area != null and not activation_area.body_entered.is_connected(_on_body_entered):
		activation_area.body_entered.connect(_on_body_entered)


func collect_for(body: Node) -> bool:
	if collected or not _is_ability_definition(ability_definition):
		return false
	if body == null or not body.has_method("grant_ability_definition"):
		return false
	if not bool(body.call("grant_ability_definition", ability_definition)):
		return false
	collect()
	request_save(true)
	return true


func _on_body_entered(body: Node) -> void:
	collect_for(body)


func _is_ability_definition(value: Resource) -> bool:
	if value == null:
		return false
	var script := value.get_script() as Script
	while script != null:
		if script == ABILITY_DEFINITION:
			return true
		script = script.get_base_script()
	return false
