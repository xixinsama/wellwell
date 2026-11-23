class_name AbilityContext
extends RefCounted

const TAG_CONTAINER := preload("res://addons/platformer_kit/core/tags/tag_container.gd")

var actor: Node
var environment: RefCounted
var data: Dictionary = {}
var _tags: RefCounted = TAG_CONTAINER.new()


func add_tag(tag: StringName) -> bool:
	return _tags.add(tag)


func remove_tag(tag: StringName) -> bool:
	return _tags.remove(tag)


func has_tag(tag: StringName) -> bool:
	return _tags.has(tag)


func has_all_tags(tags: Array) -> bool:
	return _tags.has_all(tags)


func tags() -> Array[StringName]:
	return _tags.values()
