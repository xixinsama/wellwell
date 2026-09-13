extends Node

const MODEL := preload("res://addons/input_mapping/core/input_mapping_model.gd")
const SERVICE := preload("res://addons/input_mapping/runtime/input_mapping_service.gd")
const BUTTON_SCENE := preload("res://addons/input_mapping/ui/input_binding_button.tscn")
const MENU_SCENE := preload("res://addons/input_mapping/ui/input_mapping_menu.tscn")
const TRANSLATION_PATH := "res://addons/input_mapping/translations/input_mapping.csv"

var _paths: Array[String] = []
var _actions: Array[StringName] = []


func run() -> Array[String]:
	var failures: Array[String] = []
	_assert_scene_contracts(failures)
	_assert_binding_capture_rules(failures)
	_assert_dynamic_rows_and_single_capture(failures)
	_assert_empty_state(failures)
	_assert_explicit_builtin_action_opt_in(failures)
	_assert_translation_catalog(failures)
	_cleanup()
	return failures


func _assert_scene_contracts(failures: Array[String]) -> void:
	var menu := MENU_SCENE.instantiate() as Control
	if menu == null:
		failures.append("input mapping menu scene could not be instantiated")
		return
	for node_name: String in [
		"Title", "Instruction", "HeaderGrid", "ActionsGrid", "EmptyLabel",
		"StatusLabel", "ResetButton", "BackButton",
	]:
		if menu.find_child(node_name, true, false) == null:
			failures.append("input mapping menu is missing node %s" % node_name)
	menu.free()
	var button := BUTTON_SCENE.instantiate() as Button
	if button == null:
		failures.append("input binding button scene could not be instantiated")
	else:
		button.free()


func _assert_binding_capture_rules(failures: Array[String]) -> void:
	var action := _new_action("capture", [_key(KEY_A), _joy_button(JOY_BUTTON_A)])
	var service := _new_service(_new_path("capture"), [action])
	var button := BUTTON_SCENE.instantiate() as Button
	add_child(button)
	button.call("configure", service, action, MODEL.BindingSlot.KEYBOARD_PRIMARY)
	button.call("begin_capture")
	var release := _key(KEY_R)
	release.pressed = false
	if bool(button.call("consume_capture_event", release)):
		failures.append("binding button consumed a key release")
	if not bool(button.call("is_capturing")):
		failures.append("ignored key release ended capture")
	if not bool(button.call("consume_capture_event", _key(KEY_R))):
		failures.append("binding button did not consume a compatible key press")
	if not _slot_is_single_key(service, action, MODEL.BindingSlot.KEYBOARD_PRIMARY, KEY_R):
		failures.append("compatible key capture did not update the bound action")

	button.call("configure", service, action, MODEL.BindingSlot.GAMEPAD)
	button.call("begin_capture")
	if bool(button.call("consume_capture_event", _mouse_button(MOUSE_BUTTON_LEFT))):
		failures.append("gamepad capture consumed the activating mouse input")
	if not bool(button.call("is_capturing")):
		failures.append("incompatible mouse input ended gamepad capture")
	if not bool(button.call("consume_capture_event", _key(KEY_ESCAPE))):
		failures.append("Escape did not cancel active capture")
	if bool(button.call("is_capturing")):
		failures.append("button remained in capture mode after Escape")
	var gamepad: Array[InputEvent] = service.get_slot_events(action, MODEL.BindingSlot.GAMEPAD)
	if gamepad.size() != 1 or not gamepad[0] is InputEventJoypadButton:
		failures.append("canceling capture changed the gamepad scheme")

	button.call("configure", service, action, MODEL.BindingSlot.KEYBOARD_PRIMARY)
	button.call("begin_capture")
	if not bool(button.call("consume_capture_event", _key(KEY_DELETE))):
		failures.append("Delete did not consume and clear active capture")
	if not service.get_slot_events(action, MODEL.BindingSlot.KEYBOARD_PRIMARY).is_empty():
		failures.append("Delete did not clear the active binding slot")
	button.queue_free()
	service.queue_free()


func _assert_dynamic_rows_and_single_capture(failures: Array[String]) -> void:
	var action := _new_action("row", [_key(KEY_D), _key(KEY_RIGHT), _joy_button(JOY_BUTTON_DPAD_RIGHT)])
	var service := _new_service(_new_path("row"), [action])
	var menu := MENU_SCENE.instantiate() as Control
	add_child(menu)
	menu.call("bind_service", service)
	menu.call("open_menu")
	var header_grid := menu.get_node("Panel/Content/HeaderGrid") as GridContainer
	var actions_grid := menu.get_node("Panel/Content/ActionScroll/ActionsGrid") as GridContainer
	if header_grid.get_child_count() != 4:
		failures.append("input mapping header does not contain four columns")
	if actions_grid.get_child_count() != 4:
		failures.append("one input action did not generate one label and three binding buttons")
	else:
		var first := actions_grid.get_child(1)
		var second := actions_grid.get_child(2)
		first.call("begin_capture")
		second.call("begin_capture")
		if bool(first.call("is_capturing")) or not bool(second.call("is_capturing")):
			failures.append("starting a second capture did not cancel the previous button")
	if not bool(menu.call("is_capturing")):
		failures.append("menu did not report its active binding capture")
	menu.queue_free()
	service.queue_free()


func _assert_empty_state(failures: Array[String]) -> void:
	var action := _new_action("empty", [_key(KEY_E)])
	var service := _new_service(_new_path("empty"), [action])
	var menu := MENU_SCENE.instantiate() as Control
	var missing_actions: Array[StringName] = [&"missing_input_mapping_action"]
	menu.set("included_actions", missing_actions)
	add_child(menu)
	menu.call("bind_service", service)
	menu.call("open_menu")
	var empty_label := menu.get_node("Panel/Content/ActionScroll/EmptyLabel") as Label
	if not empty_label.visible:
		failures.append(
			"menu did not show its empty state when filters removed every action (filter=%s, rows=%d)"
			% [menu.get("included_actions"), (menu.get_node("Panel/Content/ActionScroll/ActionsGrid") as GridContainer).get_child_count()]
		)
	menu.queue_free()
	service.queue_free()


func _assert_explicit_builtin_action_opt_in(failures: Array[String]) -> void:
	var action := _new_action("builtin_opt_in", [_key(KEY_U)])
	var service := _new_service(_new_path("builtin_opt_in"), [action])
	var menu := MENU_SCENE.instantiate() as Control
	var included: Array[StringName] = [&"ui_accept"]
	menu.set("included_actions", included)
	add_child(menu)
	menu.call("bind_service", service)
	menu.call("open_menu")
	var actions_grid := menu.get_node("Panel/Content/ActionScroll/ActionsGrid") as GridContainer
	if actions_grid.get_child_count() != 4:
		failures.append("explicitly included built-in ui_accept did not generate an editable row")
	menu.queue_free()
	service.queue_free()


func _assert_translation_catalog(failures: Array[String]) -> void:
	if not FileAccess.file_exists(TRANSLATION_PATH):
		failures.append("input mapping translation catalog is missing")
		return
	var file := FileAccess.open(TRANSLATION_PATH, FileAccess.READ)
	var text := file.get_as_text()
	file.close()
	if not text.begins_with("keys,en,zh_CN"):
		failures.append("input mapping translation catalog has wrong locale columns")
	for key: String in [
		"INPUT_MAPPING_TITLE", "INPUT_MAPPING_INSTRUCTION", "INPUT_MAPPING_ACTION",
		"INPUT_MAPPING_PRIMARY", "INPUT_MAPPING_SECONDARY", "INPUT_MAPPING_GAMEPAD",
		"INPUT_MAPPING_PRESS_INPUT", "INPUT_MAPPING_UNBOUND", "INPUT_MAPPING_NO_ACTIONS",
		"INPUT_MAPPING_RESET", "INPUT_MAPPING_BACK", "INPUT_MAPPING_SAVE_FAILED",
		"INPUT_MAPPING_MOUSE_LEFT", "INPUT_MAPPING_PAD_A", "INPUT_MAPPING_DPAD_LEFT",
		"INPUT_MAPPING_LEFT_STICK_LEFT",
	]:
		if not text.contains("\n%s," % key):
			failures.append("input mapping translation key is missing: %s" % key)


func _new_service(path: String, actions: Array[StringName]) -> Node:
	var service := SERVICE.new()
	service.auto_initialize = false
	add_child(service)
	service.initialize(path, actions)
	return service


func _new_action(suffix: String, events: Array[InputEvent]) -> StringName:
	var action := StringName("test_input_mapping_ui_%s_%d" % [suffix, Time.get_ticks_usec()])
	InputMap.add_action(action)
	for event: InputEvent in events:
		InputMap.action_add_event(action, event)
	_actions.append(action)
	return action


func _new_path(suffix: String) -> String:
	var path := "user://input_mapping_ui_%s_%d.cfg" % [suffix, Time.get_ticks_usec()]
	_paths.append(path)
	return path


func _slot_is_single_key(service: Node, action: StringName, slot: int, code: Key) -> bool:
	var events: Array[InputEvent] = service.get_slot_events(action, slot)
	return (
		events.size() == 1
		and events[0] is InputEventKey
		and (events[0] as InputEventKey).physical_keycode == code
	)


func _key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	return event


func _mouse_button(index: MouseButton) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = index
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
