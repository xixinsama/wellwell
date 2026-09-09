class_name ProgressionContext
extends RefCounted

var _abilities: Dictionary[StringName, bool] = {}
var _items: Dictionary[StringName, int] = {}
var _flags: Dictionary[StringName, bool] = {}


func grant_ability(ability_id: StringName) -> bool:
	if ability_id.is_empty() or _abilities.has(ability_id):
		return false
	_abilities[ability_id] = true
	return true


func revoke_ability(ability_id: StringName) -> bool:
	return _abilities.erase(ability_id)


func has_ability(ability_id: StringName) -> bool:
	return _abilities.has(ability_id)


func grant_item(item_id: StringName, count := 1) -> bool:
	if item_id.is_empty() or count <= 0:
		return false
	_items[item_id] = _items.get(item_id, 0) + count
	return true


func consume_item(item_id: StringName, count := 1) -> bool:
	if count <= 0 or item_count(item_id) < count:
		return false
	var remaining := item_count(item_id) - count
	if remaining == 0:
		_items.erase(item_id)
	else:
		_items[item_id] = remaining
	return true


func item_count(item_id: StringName) -> int:
	return _items.get(item_id, 0)


func has_item(item_id: StringName, minimum_count := 1) -> bool:
	return item_count(item_id) >= maxi(1, minimum_count)


func set_flag(flag_id: StringName, value: bool) -> bool:
	if flag_id.is_empty():
		return false
	_flags[flag_id] = value
	return true


func get_flag(flag_id: StringName, default_value := false) -> bool:
	return _flags.get(flag_id, default_value)


func to_dictionary() -> Dictionary:
	return {
		"abilities": _sorted_string_keys(_abilities),
		"items": _items.duplicate(true),
		"flags": _flags.duplicate(true),
	}


func load_dictionary(data: Dictionary) -> bool:
	var abilities: Variant = data.get("abilities", [])
	var items: Variant = data.get("items", {})
	var flags: Variant = data.get("flags", {})
	if not abilities is Array or not items is Dictionary or not flags is Dictionary:
		return false
	_abilities.clear()
	_items.clear()
	_flags.clear()
	for value: Variant in abilities:
		grant_ability(StringName(value))
	for key: Variant in items:
		grant_item(StringName(key), int(items[key]))
	for key: Variant in flags:
		set_flag(StringName(key), bool(flags[key]))
	return true


func _sorted_string_keys(values: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for key: Variant in values:
		result.append(String(key))
	result.sort()
	return result
