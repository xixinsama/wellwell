class_name SaveCodec
extends RefCounted

const SAVE_SNAPSHOT: Script = preload("res://scripts/save/save_snapshot.gd")


func encode(snapshot: RefCounted) -> String:
	if snapshot == null:
		return ""
	return JSON.stringify(snapshot.to_dictionary(), "  ", false)


func decode(text: String, expected_slot: int) -> RefCounted:
	if expected_slot < 1 or expected_slot > 3:
		return null
	var json := JSON.new()
	if json.parse(text) != OK:
		return null
	if not json.data is Dictionary:
		return null
	var snapshot: RefCounted = SAVE_SNAPSHOT.new()
	snapshot = snapshot.load_from_dictionary(json.data)
	if snapshot == null or snapshot.slot != expected_slot:
		return null
	return snapshot
