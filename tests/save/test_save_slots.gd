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
	_assert_prepare_slot_does_not_persist_or_select(failures)
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


func _assert_prepare_slot_does_not_persist_or_select(failures: Array[String]) -> void:
	var storage := EmptyStorage.new()
	var manager: Node = SAVE_MANAGER.new()
	manager.setup_storage(storage)
	if not manager.has_method("prepare_slot") or not manager.has_method("activate_snapshot"):
		failures.append("save manager is missing transactional slot startup APIs")
		manager.free()
		return
	var snapshot: RefCounted = manager.call("prepare_slot", 2)
	if snapshot == null or snapshot.slot != 2:
		failures.append("prepare_slot did not create an in-memory snapshot")
	if storage.write_count != 0 or manager.selected_slot != 0 or manager.current_snapshot != null:
		failures.append("prepare_slot persisted or selected a slot before world readiness")
	if not manager.call("activate_snapshot", snapshot):
		failures.append("activate_snapshot rejected the prepared snapshot")
	if storage.write_count != 1 or manager.selected_slot != 2 or manager.current_snapshot != snapshot:
		failures.append("activate_snapshot did not persist and select the ready slot")
	manager.free()

func _assert_manager_does_not_create_slot_on_ready(failures: Array[String]) -> void:
	var storage := EmptyStorage.new()
	var manager: Node = SAVE_MANAGER.new()
	manager.setup_storage(storage)
	manager.call("_ready")
	if storage.write_count != 0:
		failures.append("save manager created a slot before the player selected one")
	manager.free()
