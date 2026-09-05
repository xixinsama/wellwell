extends Node

const SAVE_SNAPSHOT := preload("res://scripts/save/save_snapshot.gd")

func run() -> Array[String]:
	var failures: Array[String] = []
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

