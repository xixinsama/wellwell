class_name TagContainer
extends RefCounted

var _tags: Dictionary[StringName, bool] = {}


func add(tag: StringName) -> bool:
	if tag.is_empty() or _tags.has(tag):
		return false
	_tags[tag] = true
	return true


func remove(tag: StringName) -> bool:
	return _tags.erase(tag)


func has(tag: StringName) -> bool:
	return _tags.has(tag)


func has_all(required_tags: Array) -> bool:
	for tag: Variant in required_tags:
		if not _tags.has(StringName(tag)):
			return false
	return true


func values() -> Array[StringName]:
	var result: Array[StringName] = []
	result.assign(_tags.keys())
	result.sort()
	return result

