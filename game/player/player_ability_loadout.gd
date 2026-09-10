class_name PlayerAbilityLoadout
extends Node

const ABILITY_CONTEXT := preload("res://addons/platformer_abilities/runtime/ability_context.gd")
const DASH_ID: StringName = &"dash"

@export var ability_definitions: Array[Resource] = []
@export var controller_path := NodePath("AbilityController")

var _progression: RefCounted


func bind_progression(progression: RefCounted) -> bool:
	if progression == null or not progression.has_method("grant_ability") or not progression.has_method("has_ability"):
		return false
	_progression = progression
	synchronize_unlocked_abilities()
	return true


func grant_ability_definition(definition: Resource) -> bool:
	var ability_id := _register_definition(definition)
	if ability_id.is_empty():
		return false
	var already_unlocked := _progression != null and bool(_progression.call("has_ability", ability_id))
	if _progression != null and not already_unlocked:
		if not bool(_progression.call("grant_ability", ability_id)):
			return false
	if _install_definition(definition):
		return true
	if _progression != null and not already_unlocked and _progression.has_method("revoke_ability"):
		_progression.call("revoke_ability", ability_id)
	return false


func synchronize_unlocked_abilities() -> void:
	if _progression == null:
		return
	var controller := _get_controller()
	if controller == null:
		return
	for definition: Resource in ability_definitions:
		var ability_id := _get_ability_id(definition)
		if ability_id.is_empty():
			continue
		if bool(_progression.call("has_ability", ability_id)):
			_install_definition(definition)
		elif controller.call("has_ability", ability_id):
			controller.call("remove_ability", ability_id)


func get_motion_override(
	intent: RefCounted,
	environment: RefCounted,
	facing: int
) -> Dictionary:
	var controller := _get_controller()
	if controller == null or intent == null:
		return {}
	if intent.has_method("is_action_pressed") and intent.call("is_action_pressed", DASH_ID):
		var context: RefCounted = ABILITY_CONTEXT.new()
		context.set("actor", get_parent())
		context.set("environment", environment)
		context.set("data", {
			"direction": Vector2(float(intent.get("move_axis")), 0.0),
			"facing": facing,
		})
		controller.call("try_activate", DASH_ID, context)
	var runtime := controller.call("get_runtime", DASH_ID) as RefCounted
	if runtime == null or not runtime.has_method("is_motion_overriding") or not runtime.call("is_motion_overriding"):
		return {}
	return {
		"active": true,
		"velocity": runtime.call("get_velocity_override"),
	}


func _register_definition(definition: Resource) -> StringName:
	var ability_id := _get_ability_id(definition)
	if ability_id.is_empty():
		return &""
	for registered: Resource in ability_definitions:
		if _get_ability_id(registered) == ability_id:
			return ability_id
	ability_definitions.append(definition)
	return ability_id


func _install_definition(definition: Resource) -> bool:
	var controller := _get_controller()
	var ability_id := _get_ability_id(definition)
	if controller == null or ability_id.is_empty():
		return false
	if controller.call("has_ability", ability_id):
		return true
	return bool(controller.call("add_definition", definition))


func _get_controller() -> Node:
	return get_node_or_null(controller_path)


func _get_ability_id(definition: Resource) -> StringName:
	return &"" if definition == null else StringName(definition.get("ability_id"))
