class_name PersistentId
extends Resource

const ALLOWED_CHARACTERS := "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_:-./"

@export var value: StringName


func is_valid() -> bool:
	return is_valid_value(value)


static func is_valid_value(candidate: StringName) -> bool:
	var text := String(candidate)
	if text.is_empty() or text != text.strip_edges() or not text.contains(":"):
		return false
	if text.begins_with(":") or text.ends_with(":") or text.contains("::"):
		return false
	for character: String in text:
		if ALLOWED_CHARACTERS.find(character) < 0:
			return false
	return true
