class_name PlayerAbilityLoadout
extends Node

const ABILITY_CONTEXT := preload("res://addons/platformer_abilities/runtime/ability_context.gd")
const DASH_ID: StringName = &"dash"

@export var ability_definitions: Array[Resource] = []
@export var controller_path := NodePath("AbilityController")

var _progression: RefCounted


func _ready() -> void:
	call_deferred("_install_unbound_definitions")


## Standalone scenes (room previews, component galleries, labs) have no
## ProgressionContext. Install the authored definitions so their player can
## still dash; a real game binding overwrites this through
## synchronize_unlocked_abilities().
func _install_unbound_definitions() -> void:
	if _progression != null or not is_inside_tree():
		return
	for definition: Resource in ability_definitions:
		if definition != null:
			_install_definition(definition)


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
	if intent == null:
		return {}
	try_start_dash(intent, environment, facing)
	var runtime := get_dash_runtime()
	if runtime == null or not runtime.has_method("is_motion_overriding") or not runtime.call("is_motion_overriding"):
		return {}
	return {
		"active": true,
		"velocity": runtime.call("get_velocity_override"),
	}


## Starts the Dash from a CharacterIntent if its action was pressed this frame.
## Returns true only when a new dash was activated.
func try_start_dash(
	intent: RefCounted,
	environment: RefCounted,
	facing: int
) -> bool:
	var controller := _get_controller()
	if controller == null or intent == null:
		return false
	if not intent.has_method("is_action_pressed") or not intent.call("is_action_pressed", DASH_ID):
		return false
	var context: RefCounted = ABILITY_CONTEXT.new()
	context.set("actor", get_parent())
	context.set("environment", environment)
	context.set("data", {
		"direction": Vector2(float(intent.get("move_axis")), float(intent.get("vertical_axis"))),
		"facing": facing,
	})
	return bool(controller.call("try_activate", DASH_ID, context))


func get_dash_runtime() -> RefCounted:
	var controller := _get_controller()
	if controller == null:
		return null
	return controller.call("get_runtime", DASH_ID) as RefCounted


func get_dash_definition() -> Resource:
	var runtime := get_dash_runtime()
	if runtime == null or not runtime.has_method("get_definition"):
		return null
	return runtime.call("get_definition") as Resource


func has_ability(ability_id: StringName) -> bool:
	var controller := _get_controller()
	return controller != null and bool(controller.call("has_ability", ability_id))


## Restores the Dash charge count. The controller calls this every physics frame
## while the player touches the ground or swims, so water makes the dash
## effectively unlimited while the Dash runtime still owns the count.
func update_dash_recharge(can_recharge: bool) -> void:
	if not can_recharge:
		return
	var controller := _get_controller()
	if controller == null:
		return
	var runtime := controller.call("get_runtime", DASH_ID) as RefCounted
	if runtime != null and runtime.has_method("refill"):
		runtime.call("refill")


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
