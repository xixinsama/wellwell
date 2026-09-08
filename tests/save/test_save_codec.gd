extends Node

const SAVE_SNAPSHOT: Script = preload("res://addons/platformer_kit/save/save_snapshot.gd")
const SAVE_CODEC: Script = preload("res://addons/platformer_kit/save/save_codec.gd")
const SAVE_MANAGER: Script = preload("res://addons/platformer_kit/save/save_manager.gd")


class RecordingStorage extends RefCounted:
	var written: RefCounted

	func write_slot(snapshot: RefCounted) -> bool:
		written = snapshot
		return true


func run() -> Array[String]:
	var failures: Array[String] = []
	_assert_round_trip_preserves_explored_cells(failures)
	_assert_invalid_data_is_rejected(failures)
	_assert_invalid_load_does_not_mutate_existing_snapshot(failures)
	_assert_commits_announce_the_snapshot_before_writing(failures)
	return failures


func _assert_round_trip_preserves_explored_cells(failures: Array[String]) -> void:
	var snapshot: RefCounted = SAVE_SNAPSHOT.new()
	snapshot.slot = 1
	snapshot.respawn_position = Vector2(-120, 48)
	snapshot.add_explored_cell("level_01:-15,6")
	snapshot.add_explored_cell("level_01:-14,6")
	snapshot.add_explored_cell("level_01:-15,6")
	var codec: RefCounted = SAVE_CODEC.new()

	var decoded: RefCounted = codec.decode(codec.encode(snapshot), 1)

	if decoded == null:
		failures.append("decoded snapshot was null")
		return
	if decoded.slot != 1:
		failures.append("slot did not round trip")
	if decoded.respawn_position != Vector2(-120, 48):
		failures.append("respawn position did not round trip")
	if decoded.get_explored_cells() != ["level_01:-14,6", "level_01:-15,6"]:
		failures.append("explored cells were not unique and sorted")


func _assert_invalid_data_is_rejected(failures: Array[String]) -> void:
	var codec: RefCounted = SAVE_CODEC.new()
	if codec.decode("{not valid json", 1) != null:
		failures.append("invalid JSON decoded")
	if codec.decode("[]", 1) != null:
		failures.append("non-dictionary JSON decoded")
	var snapshot: RefCounted = SAVE_SNAPSHOT.new()
	snapshot.slot = 2
	if codec.decode(codec.encode(snapshot), 1) != null:
		failures.append("mismatched slot decoded")


func _assert_invalid_load_does_not_mutate_existing_snapshot(failures: Array[String]) -> void:
	var snapshot: RefCounted = SAVE_SNAPSHOT.new()
	snapshot.slot = 1
	snapshot.world_id = "preserved_world"
	snapshot.add_explored_cell("preserved:cell")
	snapshot.add_explored_chunk("preserved:chunk")
	snapshot.set_entity_state("preserved:entity", {"active": true})
	var invalid_data: Dictionary = snapshot.to_dictionary()
	invalid_data["world_id"] = "invalid_world"
	invalid_data["explored_cells"] = ["replacement:cell"]
	invalid_data["explored_chunks"] = ["replacement:chunk"]
	invalid_data["entity_states"] = {"replacement:entity": "not_a_dictionary"}
	if snapshot.load_from_dictionary(invalid_data) != null:
		failures.append("snapshot accepted invalid entity state data")
		return
	if snapshot.world_id != "preserved_world":
		failures.append("invalid load mutated snapshot metadata")
	if not snapshot.has_explored_cell("preserved:cell") or snapshot.has_explored_cell("replacement:cell"):
		failures.append("invalid load mutated explored cells")
	if not snapshot.has_explored_chunk("preserved:chunk") or snapshot.has_explored_chunk("replacement:chunk"):
		failures.append("invalid load mutated explored chunks")
	if not bool(snapshot.get_entity_state("preserved:entity").get("active", false)):
		failures.append("invalid load mutated entity states")


func _assert_commits_announce_the_snapshot_before_writing(failures: Array[String]) -> void:
	var manager: Node = SAVE_MANAGER.new()
	var storage := RecordingStorage.new()
	var snapshot: RefCounted = SAVE_SNAPSHOT.new()
	snapshot.slot = 1
	manager.setup_storage(storage)
	manager.current_snapshot = snapshot
	if not manager.has_signal("snapshot_committing"):
		failures.append("SaveManager must announce a snapshot before writing it")
	else:
		manager.connect("snapshot_committing", func(target: RefCounted) -> void:
			target.set_entity_state("world:room:entity", {"persisted": true})
		)
		if not manager.quick_save():
			failures.append("quick save failed")
		elif not bool(storage.written.get_entity_state("world:room:entity").get("persisted", false)):
			failures.append("quick save wrote before runtime persistence listeners ran")
	manager.free()
