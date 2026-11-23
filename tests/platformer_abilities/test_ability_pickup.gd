extends Node

const PICKUP_SCENE := "res://addons/platformer_abilities/entities/ability_pickup.tscn"
const ABILITY_DEFINITION := preload("res://addons/platformer_abilities/runtime/ability_definition.gd")
const SAVE_SNAPSHOT := preload("res://addons/platformer_kit/save/save_snapshot.gd")


class AbilityReceiver extends Node:
	var accepted := true
	var definitions: Array[Resource] = []

	func grant_ability_definition(definition: Resource) -> bool:
		if not accepted:
			return false
		if not definitions.has(definition):
			definitions.append(definition)
		return true


func run() -> Array[String]:
	var failures: Array[String] = []
	if not ResourceLoader.exists(PICKUP_SCENE, "PackedScene"):
		return ["reusable AbilityPickup scene is missing"]
	_assert_invalid_collection_keeps_pickup(failures)
	_assert_successful_collection_persists(failures)
	_assert_duplicate_confirmation_and_restore(failures)
	_assert_contact_collection(failures)
	return failures


func _assert_invalid_collection_keeps_pickup(failures: Array[String]) -> void:
	var pickup := _make_pickup(null)
	var receiver := AbilityReceiver.new()
	if pickup.collect_for(receiver) or pickup.collected or not pickup.visible:
		failures.append("AbilityPickup collected without a definition")
	pickup.ability_definition = _make_definition()
	var incompatible := Node.new()
	if pickup.collect_for(incompatible) or pickup.collected:
		failures.append("AbilityPickup collected for an incompatible body")
	incompatible.free()
	receiver.accepted = false
	if pickup.collect_for(receiver) or pickup.collected:
		failures.append("AbilityPickup collected after the receiver rejected the grant")
	pickup.free()
	receiver.free()


func _assert_successful_collection_persists(failures: Array[String]) -> void:
	var definition := _make_definition()
	var snapshot: RefCounted = SAVE_SNAPSHOT.new()
	var pickup := _make_pickup(definition, snapshot)
	var receiver := AbilityReceiver.new()
	var requests: Array[bool] = []
	pickup.save_requested.connect(func(immediate: bool) -> void: requests.append(immediate))
	if not pickup.collect_for(receiver):
		failures.append("AbilityPickup rejected a compatible receiver")
	if receiver.definitions != [definition]:
		failures.append("AbilityPickup did not grant its configured definition")
	if not pickup.collected or pickup.visible:
		failures.append("AbilityPickup did not hide after collection")
	if not bool(snapshot.get_entity_state("world_a:room_a:ability_pickup").get("collected", false)):
		failures.append("AbilityPickup did not persist collection state")
	if requests != [true]:
		failures.append("AbilityPickup did not request one immediate save")
	pickup.free()
	receiver.free()


func _assert_duplicate_confirmation_and_restore(failures: Array[String]) -> void:
	var definition := _make_definition()
	var receiver := AbilityReceiver.new()
	receiver.definitions.append(definition)
	var pickup := _make_pickup(definition)
	if not pickup.collect_for(receiver) or not pickup.collected:
		failures.append("AbilityPickup did not accept confirmed duplicate ownership")
	pickup.free()
	receiver.free()

	var restored := _make_pickup(definition)
	restored.apply_save_state({"collected": true})
	if not restored.collected or restored.visible:
		failures.append("AbilityPickup did not restore its persistent hidden state")
	restored.free()


func _assert_contact_collection(failures: Array[String]) -> void:
	var pickup := _make_pickup(_make_definition())
	var receiver := AbilityReceiver.new()
	var activation_area := pickup.get_node("ActivationArea") as Area2D
	if activation_area.collision_layer != 0 or activation_area.collision_mask != 2:
		failures.append("AbilityPickup contact area does not detect the player collision layer")
	activation_area.emit_signal("body_entered", receiver)
	if not pickup.collected:
		failures.append("AbilityPickup did not collect on body entry")
	pickup.free()
	receiver.free()


func _make_pickup(definition: Resource, snapshot: RefCounted = null) -> Node:
	var pickup := (load(PICKUP_SCENE) as PackedScene).instantiate()
	pickup.ability_definition = definition
	pickup.entity_id = "ability_pickup"
	pickup.setup_entity({
		"world_id": "world_a",
		"room_id": "room_a",
		"entity_state_sink": snapshot if snapshot != null else SAVE_SNAPSHOT.new(),
	})
	add_child(pickup)
	return pickup


func _make_definition() -> Resource:
	var definition: Resource = ABILITY_DEFINITION.new()
	definition.ability_id = &"dash"
	return definition
