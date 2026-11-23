extends Node

const WORLD_ENTITY := preload("res://addons/platformer_kit/world/entities/world_entity.gd")
const SWITCH_ENTITY := preload("res://addons/platformer_kit/world/entities/switch_entity.gd")
const PICKUP_ENTITY := preload("res://addons/platformer_kit/world/entities/pickup_entity.gd")
const ROOM_ENTRANCE := preload("res://addons/platformer_kit/world/entities/room_entrance.gd")


class StateSink extends RefCounted:
	var states: Dictionary = {}

	func set_entity_state(key: String, state: Dictionary) -> void:
		states[key] = state.duplicate(true)

func run() -> Array[String]:
	var failures: Array[String] = []
	var entity: Node = WORLD_ENTITY.new()
	entity.entity_id = "switch_01"
	entity.setup_entity({"world_id": "world_01", "room_id": "room_a"})
	if entity.get_save_key() != "world_01:room_a:switch_01":
		failures.append("world entity did not build a stable save key from setup context")
	entity.persistent_id = &"switch:forest:001"
	if entity.get_save_key() != "switch:forest:001":
		failures.append("world entity did not prefer its explicit persistent_id")
	if entity.get_persistent_id() != &"switch:forest:001":
		failures.append("world entity did not expose the Saveable persistent ID contract")
	entity.free()

	var switch_entity: Node = SWITCH_ENTITY.new()
	switch_entity.activated = true
	var switch_state: Dictionary = switch_entity.get_save_state()
	switch_entity.activated = false
	switch_entity.apply_save_state(switch_state)
	if not switch_entity.activated:
		failures.append("switch state did not round trip")
	switch_entity.free()

	var pickup: Node = PICKUP_ENTITY.new()
	pickup.collected = true
	var pickup_state: Dictionary = pickup.get_save_state()
	pickup.collected = false
	pickup.apply_save_state(pickup_state)
	if not pickup.collected:
		failures.append("pickup state did not round trip")
	pickup.free()

	_assert_entity_mutations_commit_to_the_state_sink(failures)
	_assert_entity_emits_save_requests(failures)

	var entrance: Node = ROOM_ENTRANCE.new()
	for property_info: Dictionary in entrance.get_property_list():
		var property_name := String(property_info.get("name", ""))
		if property_name in ["target_room_id", "target_spawn_id"]:
			failures.append("room entrance still serializes a transition target")
	entrance.free()
	return failures


func _assert_entity_emits_save_requests(failures: Array[String]) -> void:
	var entity: Node = WORLD_ENTITY.new()
	if not entity.has_signal("save_requested") or not entity.has_method("request_save"):
		failures.append("world entities must expose generic save requests")
		entity.free()
		return
	var requests: Array[bool] = []
	entity.connect("save_requested", func(immediate: bool) -> void: requests.append(immediate))
	entity.call("request_save")
	entity.call("request_save", true)
	if requests != [false, true]:
		failures.append("world entity save requests did not preserve immediate intent")
	entity.free()


func _assert_entity_mutations_commit_to_the_state_sink(failures: Array[String]) -> void:
	var pickup: Node = PICKUP_ENTITY.new()
	var sink := StateSink.new()
	pickup.entity_id = "pickup_01"
	pickup.persistent = true
	pickup.setup_entity({
		"world_id": "world_01",
		"room_id": "room_a",
		"entity_state_sink": sink,
	})
	if not pickup.has_method("commit_save_state"):
		failures.append("persistent entities must expose commit_save_state")
	else:
		pickup.collect()
		var state: Dictionary = sink.states.get("world_01:room_a:pickup_01", {})
		if not bool(state.get("collected", false)):
			failures.append("collecting a pickup must immediately write its state")
	pickup.free()
