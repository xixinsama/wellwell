extends Node

const SAVE_SNAPSHOT: Script = preload("res://scripts/save/save_snapshot.gd")
const SAVE_CODEC: Script = preload("res://scripts/save/save_codec.gd")


func run() -> Array[String]:
	var failures: Array[String] = []
	_assert_round_trip_preserves_explored_cells(failures)
	_assert_invalid_data_is_rejected(failures)
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
