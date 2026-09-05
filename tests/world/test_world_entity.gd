extends Node

const WORLD_ENTITY := preload("res://scripts/world/world_entity.gd")
const SWITCH_ENTITY := preload("res://scripts/world/switch_entity.gd")
const PICKUP_ENTITY := preload("res://scripts/world/pickup_entity.gd")
const ROOM_ENTRANCE := preload("res://scripts/world/room_entrance.gd")

func run() -> Array[String]:
	var failures: Array[String] = []
	var entity: Node = WORLD_ENTITY.new()
	entity.entity_id = "switch_01"
	entity.setup_entity({"world_id": "world_01", "room_id": "room_a"})
	if entity.get_save_key() != "world_01:room_a:switch_01":
		failures.append("world entity did not build a stable save key from setup context")
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

	var entrance: Node = ROOM_ENTRANCE.new()
	entrance.target_room_id = "legacy_room"
	entrance.target_spawn_id = "legacy_spawn"
	if entrance.target_room_id != "legacy_room" or entrance.target_spawn_id != "legacy_spawn":
		failures.append("legacy room entrance destination fields were not readable")
	for property_info: Dictionary in entrance.get_property_list():
		var property_name := String(property_info.get("name", ""))
		if property_name != "target_room_id" and property_name != "target_spawn_id":
			continue
		var usage := int(property_info.get("usage", 0))
		if not usage & PROPERTY_USAGE_STORAGE or usage & PROPERTY_USAGE_EDITOR:
			failures.append("legacy room entrance destination remained editable instead of storage-only")
	entrance.free()
	return failures
