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
	_assert_respawn_updates_are_validated(failures)
	_assert_round_trip_preserves_module_state(failures)
	_assert_invalid_data_is_rejected(failures)
	_assert_invalid_load_does_not_mutate_existing_snapshot(failures)
	_assert_commits_announce_the_snapshot_before_writing(failures)
	_assert_resume_state_round_trip(failures)
	_assert_invalid_resume_state_is_optional(failures)
	return failures


func _assert_respawn_updates_are_validated(failures: Array[String]) -> void:
	var snapshot: RefCounted = SAVE_SNAPSHOT.new()
	snapshot.respawn_room_id = "old_room"
	snapshot.respawn_spawn_id = "old_spawn"
	snapshot.respawn_position = Vector2(4, 8)
	if not snapshot.has_method("set_respawn"):
		failures.append("SaveSnapshot is missing validated set_respawn")
		return
	if snapshot.call("set_respawn", "", "checkpoint", Vector2.ZERO):
		failures.append("SaveSnapshot accepted an empty respawn room id")
	if snapshot.call("set_respawn", "room_a", "", Vector2.ZERO):
		failures.append("SaveSnapshot accepted an empty respawn spawn id")
	if snapshot.call("set_respawn", "room_a", "checkpoint", Vector2(INF, 0)):
		failures.append("SaveSnapshot accepted a non-finite respawn position")
	if snapshot.respawn_room_id != "old_room" or snapshot.respawn_position != Vector2(4, 8):
		failures.append("invalid respawn data mutated the snapshot")
	if not snapshot.call("set_respawn", "room_a", "checkpoint", Vector2(12, 24)):
		failures.append("SaveSnapshot rejected valid respawn data")
	elif snapshot.respawn_room_id != "room_a" or snapshot.respawn_spawn_id != "checkpoint" or snapshot.respawn_position != Vector2(12, 24):
		failures.append("SaveSnapshot did not apply valid respawn data atomically")


func _assert_round_trip_preserves_module_state(failures: Array[String]) -> void:
	var snapshot: RefCounted = SAVE_SNAPSHOT.new()
	snapshot.slot = 1
	snapshot.respawn_position = Vector2(-120, 48)
	snapshot.set_module_state(&"test_module", {"visited": ["room_a"]})
	var codec: RefCounted = SAVE_CODEC.new()

	var decoded: RefCounted = codec.decode(codec.encode(snapshot), 1)

	if decoded == null:
		failures.append("decoded snapshot was null")
		return
	if decoded.slot != 1:
		failures.append("slot did not round trip")
	if decoded.respawn_position != Vector2(-120, 48):
		failures.append("respawn position did not round trip")
	if decoded.get_module_state(&"test_module") != {"visited": ["room_a"]}:
		failures.append("generic module state did not round trip")


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
	snapshot.set_module_state(&"preserved_module", {"active": true})
	snapshot.set_entity_state("preserved:entity", {"active": true})
	var invalid_data: Dictionary = snapshot.to_dictionary()
	invalid_data["world_id"] = "invalid_world"
	invalid_data["module_states"] = {"replacement_module": {"active": true}}
	invalid_data["entity_states"] = {"replacement:entity": "not_a_dictionary"}
	if snapshot.load_from_dictionary(invalid_data) != null:
		failures.append("snapshot accepted invalid entity state data")
		return
	if snapshot.world_id != "preserved_world":
		failures.append("invalid load mutated snapshot metadata")
	if not bool(snapshot.get_module_state(&"preserved_module").get("active", false)) or not snapshot.get_module_state(&"replacement_module").is_empty():
		failures.append("invalid load mutated module states")
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


func _assert_resume_state_round_trip(failures: Array[String]) -> void:
	var snapshot: RefCounted = SAVE_SNAPSHOT.new()
	snapshot.slot = 1
	if not snapshot.has_method("set_resume_state"):
		failures.append("SaveSnapshot is missing set_resume_state")
		return
	if not snapshot.call("set_resume_state", Vector2(12, 34), Vector2(5, -6)):
		failures.append("SaveSnapshot rejected a finite resume transform")
	var codec: RefCounted = SAVE_CODEC.new()
	var decoded: RefCounted = codec.decode(codec.encode(snapshot), 1)
	if decoded == null:
		failures.append("resume state round trip lost the snapshot")
		return
	if decoded.get("has_resume") != true:
		failures.append("resume state flag did not round trip")
	if Vector2(decoded.get("resume_position")) != Vector2(12, 34):
		failures.append("resume position did not round trip")
	if Vector2(decoded.get("resume_velocity")) != Vector2(5, -6):
		failures.append("resume velocity did not round trip")
	decoded.call("clear_resume_state")
	if decoded.get("has_resume") == true or not (decoded.to_dictionary().get("player_resume", {}) as Dictionary).is_empty():
		failures.append("clear_resume_state left data behind")


func _assert_invalid_resume_state_is_optional(failures: Array[String]) -> void:
	var snapshot: RefCounted = SAVE_SNAPSHOT.new()
	snapshot.slot = 1
	snapshot.world_id = "kept_world"
	var data: Dictionary = snapshot.to_dictionary()
	data["player_resume"] = {"position": {"x": "bad", "y": 0}, "velocity": {"x": 0, "y": 0}}
	var decoded: RefCounted = SAVE_CODEC.new().decode(JSON.stringify(data), 1)
	if decoded == null:
		failures.append("malformed optional resume data rejected the whole save")
	elif decoded.world_id != "kept_world" or decoded.get("has_resume") == true:
		failures.append("malformed optional resume data was not ignored")
