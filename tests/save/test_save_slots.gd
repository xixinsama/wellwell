extends Node

const SAVE_SNAPSHOT := preload("res://scripts/save/save_snapshot.gd")
const SAVE_MANAGER := preload("res://scripts/save/save_manager.gd")

class EmptyStorage extends RefCounted:
	var write_count := 0

	func read_slot(_slot: int) -> RefCounted:
		return null

	func write_slot(_snapshot: RefCounted) -> bool:
		write_count += 1
		return true

	func delete_slot(_slot: int) -> bool:
		return true

func run() -> Array[String]:
	var failures: Array[String] = []
	_assert_manager_does_not_create_slot_on_ready(failures)
	var source: RefCounted = SAVE_SNAPSHOT.new()
	source.slot = 1
	source.world_id = "world_01"
	source.current_room_id = "room_a"
	source.add_explored_chunk("world_01:chunk:0,0")
	source.set_entity_state("world_01:room_a:switch", {"activated": true})
	var restored: RefCounted = SAVE_SNAPSHOT.from_dictionary(source.to_dictionary())
	if restored == null:
		failures.append("extended save snapshot could not decode")
		return failures
	if restored.world_id != "world_01" or restored.current_room_id != "room_a":
		failures.append("room progress did not round trip")
	if not restored.has_explored_chunk("world_01:chunk:0,0"):
		failures.append("explored chunk did not round trip")
	if not bool(restored.get_entity_state("world_01:room_a:switch").get("activated", false)):
		failures.append("entity state did not round trip")
	return failures

func _assert_manager_does_not_create_slot_on_ready(failures: Array[String]) -> void:
	var storage := EmptyStorage.new()
	var manager: Node = SAVE_MANAGER.new()
	manager.setup_storage(storage)
	manager.call("_ready")
	if storage.write_count != 0:
		failures.append("save manager created a slot before the player selected one")
	manager.free()
