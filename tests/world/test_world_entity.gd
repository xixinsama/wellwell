extends Node

const WORLD_ENTITY := preload("res://scripts/world/world_entity.gd")
const SWITCH_ENTITY := preload("res://scripts/world/switch_entity.gd")
const PICKUP_ENTITY := preload("res://scripts/world/pickup_entity.gd")

func run() -> Array[String]:
	var failures: Array[String] = []
	var entity: Node = WORLD_ENTITY.new()
	entity.entity_id = "switch_01"
	entity.room_id = "room_a"
	entity.set_meta("world_id", "world_01")
	if entity.get_save_key() != "world_01:room_a:switch_01":
		failures.append("world entity save key was not stable")
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
	return failures

