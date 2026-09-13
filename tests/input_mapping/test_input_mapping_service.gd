extends Node

const MODEL := preload("res://addons/input_mapping/core/input_mapping_model.gd")
const STORE := preload("res://addons/input_mapping/core/input_mapping_store.gd")
const SERVICE := preload("res://addons/input_mapping/runtime/input_mapping_service.gd")

var _paths: Array[String] = []
var _actions: Array[StringName] = []


func run() -> Array[String]:
	var failures: Array[String] = []
	_assert_persistence_round_trip_and_restore(failures)
	_assert_duplicate_bindings_are_allowed(failures)
	_assert_stale_and_invalid_overrides_are_ignored(failures)
	_assert_reload_is_idempotent(failures)
	_assert_save_failure_keeps_runtime_change(failures)
	_cleanup()
	return failures


func _assert_persistence_round_trip_and_restore(failures: Array[String]) -> void:
	var action := _new_action("round_trip", [_key(KEY_A), _key(KEY_LEFT), _joy_button(JOY_BUTTON_A)])
	var defaults := _copy_action_events(action)
	var path := _new_path("round_trip")
	var service := _new_service(path, [action])
	var replacement := _key(KEY_Q)
	if not service.replace_slot(action, MODEL.BindingSlot.KEYBOARD_PRIMARY, replacement):
		failures.append("service rejected a compatible primary replacement")
	if not FileAccess.file_exists(path):
		failures.append("service did not persist the first customized action")

	_set_action_events(action, defaults)
	service.queue_free()
	var reloaded := _new_service(path, [action])
	if not _slot_is_single_key(reloaded, action, MODEL.BindingSlot.KEYBOARD_PRIMARY, KEY_Q):
		failures.append("saved primary binding did not survive service reload")
	if not reloaded.clear_slot(action, MODEL.BindingSlot.KEYBOARD_SECONDARY):
		failures.append("service rejected clearing a populated secondary scheme")
	if not reloaded.get_slot_events(action, MODEL.BindingSlot.KEYBOARD_SECONDARY).is_empty():
		failures.append("secondary scheme was still populated after clearing")
	if not reloaded.restore_defaults():
		failures.append("service failed to restore authored defaults")
	if not _events_match(InputMap.action_get_events(action), defaults):
		failures.append("restore defaults did not restore the authored event snapshot")
	if FileAccess.file_exists(path):
		failures.append("restore defaults did not remove saved overrides")
	reloaded.queue_free()


func _assert_duplicate_bindings_are_allowed(failures: Array[String]) -> void:
	var first := _new_action("duplicate_first", [_key(KEY_A)])
	var second := _new_action("duplicate_second", [_key(KEY_B)])
	var path := _new_path("duplicates")
	var service := _new_service(path, [first, second])
	var shared := _key(KEY_R)
	if not service.replace_slot(first, MODEL.BindingSlot.KEYBOARD_PRIMARY, shared):
		failures.append("first action rejected shared binding")
	if not service.replace_slot(second, MODEL.BindingSlot.KEYBOARD_PRIMARY, shared):
		failures.append("second action rejected duplicate binding")
	if (
		not _slot_is_single_key(service, first, MODEL.BindingSlot.KEYBOARD_PRIMARY, KEY_R)
		or not _slot_is_single_key(service, second, MODEL.BindingSlot.KEYBOARD_PRIMARY, KEY_R)
	):
		failures.append("assigning a duplicate binding removed it from another action")
	service.queue_free()


func _assert_stale_and_invalid_overrides_are_ignored(failures: Array[String]) -> void:
	var current := _new_action("current", [_key(KEY_C), _joy_button(JOY_BUTTON_B)])
	var added := _new_action("added", [_key(KEY_N)])
	var stale := StringName("__input_mapping_stale_action")
	var path := _new_path("invalid")
	var config := ConfigFile.new()
	config.set_value("meta", "schema_version", STORE.SCHEMA_VERSION)
	config.set_value("actions", "overrides", {
		String(current): {
			"customized": true,
			"primary": [_joy_button(JOY_BUTTON_X)],
			"secondary": [_key(KEY_V)],
			"gamepad": [_key(KEY_G)],
		},
		String(stale): {
			"customized": true,
			"primary": [_key(KEY_Z)],
			"secondary": [],
			"gamepad": [],
		},
	})
	if config.save(path) != OK:
		failures.append("test could not create invalid override fixture")
		return
	var service := _new_service(path, [current, added])
	if not _slot_is_single_key(service, current, MODEL.BindingSlot.KEYBOARD_PRIMARY, KEY_C):
		failures.append("wrong-category primary override replaced the authored default")
	if not _slot_is_single_key(service, current, MODEL.BindingSlot.KEYBOARD_SECONDARY, KEY_V):
		failures.append("valid secondary entry was not applied beside invalid entries")
	var gamepad: Array[InputEvent] = service.get_slot_events(current, MODEL.BindingSlot.GAMEPAD)
	if gamepad.size() != 1 or not gamepad[0] is InputEventJoypadButton:
		failures.append("wrong-category gamepad override replaced the authored default")
	if not _slot_is_single_key(service, added, MODEL.BindingSlot.KEYBOARD_PRIMARY, KEY_N):
		failures.append("new action without an override did not retain its authored default")
	if service.get_actions().has(stale):
		failures.append("stale saved action was recreated")
	service.queue_free()


func _assert_reload_is_idempotent(failures: Array[String]) -> void:
	var action := _new_action("reload", [_key(KEY_T)])
	var path := _new_path("reload")
	var service := _new_service(path, [action])
	service.replace_slot(action, MODEL.BindingSlot.KEYBOARD_PRIMARY, _key(KEY_Y))
	if not service.reload_overrides() or not service.reload_overrides():
		failures.append("service rejected a valid repeated reload")
	var events := InputMap.action_get_events(action)
	if events.size() != 1 or not _event_is_key(events[0], KEY_Y):
		failures.append("reloading overrides duplicated or changed the saved binding")
	service.queue_free()


func _assert_save_failure_keeps_runtime_change(failures: Array[String]) -> void:
	var action := _new_action("save_failure", [_key(KEY_F)])
	var path := "user://missing_input_mapping_test_%d/input_mappings.cfg" % Time.get_ticks_usec()
	var service := _new_service(path, [action])
	var messages: Array[String] = []
	service.persistence_failed.connect(func(message: String) -> void: messages.append(message))
	if service.replace_slot(action, MODEL.BindingSlot.KEYBOARD_PRIMARY, _key(KEY_H)):
		failures.append("service reported success when persistence failed")
	if not _slot_is_single_key(service, action, MODEL.BindingSlot.KEYBOARD_PRIMARY, KEY_H):
		failures.append("save failure rolled back the live input replacement")
	if messages.is_empty():
		failures.append("save failure did not emit persistence_failed")
	service.queue_free()


func _new_service(path: String, actions: Array[StringName]) -> Node:
	var service := SERVICE.new()
	service.auto_initialize = false
	add_child(service)
	service.initialize(path, actions)
	return service


func _new_action(suffix: String, events: Array[InputEvent]) -> StringName:
	var action := StringName("__input_mapping_%s_%d" % [suffix, Time.get_ticks_usec()])
	InputMap.add_action(action)
	for event: InputEvent in events:
		InputMap.action_add_event(action, event)
	_actions.append(action)
	return action


func _new_path(suffix: String) -> String:
	var path := "user://input_mapping_%s_%d.cfg" % [suffix, Time.get_ticks_usec()]
	_paths.append(path)
	return path


func _copy_action_events(action: StringName) -> Array[InputEvent]:
	var copies: Array[InputEvent] = []
	for event: InputEvent in InputMap.action_get_events(action):
		copies.append(event.duplicate(true) as InputEvent)
	return copies


func _set_action_events(action: StringName, events: Array[InputEvent]) -> void:
	InputMap.action_erase_events(action)
	for event: InputEvent in events:
		InputMap.action_add_event(action, event)


func _slot_is_single_key(service: Node, action: StringName, slot: int, code: Key) -> bool:
	var events: Array[InputEvent] = service.get_slot_events(action, slot)
	return events.size() == 1 and _event_is_key(events[0], code)


func _events_match(actual: Array[InputEvent], expected: Array[InputEvent]) -> bool:
	if actual.size() != expected.size():
		return false
	for index: int in actual.size():
		if actual[index].as_text() != expected[index].as_text():
			return false
	return true


func _event_is_key(event: InputEvent, code: Key) -> bool:
	return event is InputEventKey and (event as InputEventKey).physical_keycode == code


func _key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	return event


func _joy_button(index: JoyButton) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = index
	event.pressed = true
	return event


func _cleanup() -> void:
	for action: StringName in _actions:
		if InputMap.has_action(action):
			InputMap.erase_action(action)
	for path: String in _paths:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
