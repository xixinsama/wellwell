class_name InputMappingModel
extends RefCounted

enum BindingSlot {
	KEYBOARD_PRIMARY,
	KEYBOARD_SECONDARY,
	GAMEPAD,
}

const UNSUPPORTED_GROUP := "unsupported"
const JOYPAD_AXIS_CAPTURE_THRESHOLD := 0.5


static func discover_project_actions(
	source_actions: Array[StringName] = [],
	included_actions: Array[StringName] = [],
	excluded_actions: Array[StringName] = [],
	preferred_order: Array[StringName] = []
) -> Array[StringName]:
	var source := source_actions if not source_actions.is_empty() else _read_project_actions()
	var candidates: Array[StringName] = []
	for action: StringName in source:
		if candidates.has(action):
			continue
		if not included_actions.is_empty() and not included_actions.has(action):
			continue
		if excluded_actions.has(action):
			continue
		candidates.append(action)

	var ordered: Array[StringName] = []
	for action: StringName in preferred_order:
		if candidates.has(action) and not ordered.has(action):
			ordered.append(action)
	for action: StringName in candidates:
		if not ordered.has(action):
			ordered.append(action)
	return ordered


static func classify_events(events: Array[InputEvent]) -> Dictionary:
	var result := {
		BindingSlot.KEYBOARD_PRIMARY: [] as Array[InputEvent],
		BindingSlot.KEYBOARD_SECONDARY: [] as Array[InputEvent],
		BindingSlot.GAMEPAD: [] as Array[InputEvent],
		UNSUPPORTED_GROUP: [] as Array[InputEvent],
	}
	var found_primary := false
	for event: InputEvent in events:
		if event is InputEventKey or event is InputEventMouseButton:
			var slot := BindingSlot.KEYBOARD_SECONDARY if found_primary else BindingSlot.KEYBOARD_PRIMARY
			(result[slot] as Array[InputEvent]).append(event)
			found_primary = true
		elif event is InputEventJoypadButton or event is InputEventJoypadMotion:
			(result[BindingSlot.GAMEPAD] as Array[InputEvent]).append(event)
		else:
			(result[UNSUPPORTED_GROUP] as Array[InputEvent]).append(event)
	return result


static func get_slot_events(events: Array[InputEvent], slot: int) -> Array[InputEvent]:
	if not _is_valid_slot(slot):
		return []
	var groups := classify_events(events)
	return duplicate_events(groups[slot] as Array[InputEvent])


static func is_event_compatible(event: InputEvent, slot: int) -> bool:
	if not _is_valid_slot(slot):
		return false
	if slot == BindingSlot.GAMEPAD:
		if event is InputEventJoypadButton:
			return (event as InputEventJoypadButton).pressed
		if event is InputEventJoypadMotion:
			return absf((event as InputEventJoypadMotion).axis_value) >= JOYPAD_AXIS_CAPTURE_THRESHOLD
		return false
	if event is InputEventKey:
		var key_event := event as InputEventKey
		return key_event.pressed and not key_event.echo
	if event is InputEventMouseButton:
		return (event as InputEventMouseButton).pressed
	return false


static func normalize_event(event: InputEvent) -> InputEvent:
	var normalized := event.duplicate(true) as InputEvent
	if normalized == null:
		return event
	normalized.device = -1
	if normalized is InputEventJoypadMotion:
		var axis_event := normalized as InputEventJoypadMotion
		axis_event.axis_value = -1.0 if axis_event.axis_value < 0.0 else 1.0
	return normalized


static func replace_slot_events(
	events: Array[InputEvent],
	slot: int,
	replacements: Array[InputEvent]
) -> Array[InputEvent]:
	if not _is_valid_slot(slot):
		return duplicate_events(events)
	var groups := classify_events(events)
	var normalized_replacements: Array[InputEvent] = []
	for event: InputEvent in replacements:
		if is_event_compatible(event, slot):
			normalized_replacements.append(normalize_event(event))
	groups[slot] = normalized_replacements

	var rebuilt: Array[InputEvent] = []
	for group_key: Variant in [
		BindingSlot.KEYBOARD_PRIMARY,
		BindingSlot.KEYBOARD_SECONDARY,
		BindingSlot.GAMEPAD,
		UNSUPPORTED_GROUP,
	]:
		rebuilt.append_array(groups[group_key] as Array[InputEvent])
	return rebuilt


static func duplicate_events(events: Array[InputEvent]) -> Array[InputEvent]:
	var copies: Array[InputEvent] = []
	for event: InputEvent in events:
		var copy := event.duplicate(true) as InputEvent
		copies.append(copy if copy != null else event)
	return copies


static func _read_project_actions() -> Array[StringName]:
	var actions: Array[StringName] = []
	for property: Dictionary in ProjectSettings.get_property_list():
		var property_name := String(property.get("name", ""))
		if not property_name.begins_with("input/"):
			continue
		var action := StringName(property_name.trim_prefix("input/"))
		if not action.is_empty() and InputMap.has_action(action) and not actions.has(action):
			actions.append(action)
	return actions


static func _is_valid_slot(slot: int) -> bool:
	return slot >= BindingSlot.KEYBOARD_PRIMARY and slot <= BindingSlot.GAMEPAD
