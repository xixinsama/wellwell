extends Node

const MODEL := preload("res://addons/input_mapping/core/input_mapping_model.gd")


func run() -> Array[String]:
	var failures: Array[String] = []
	_assert_event_classification(failures)
	_assert_slot_replacement(failures)
	_assert_capture_compatibility_and_axis_normalization(failures)
	_assert_action_filtering_and_order(failures)
	return failures


func _assert_event_classification(failures: Array[String]) -> void:
	var key_a := _key(KEY_A)
	var key_left := _key(KEY_LEFT)
	var pad_button := _joy_button(JOY_BUTTON_DPAD_LEFT)
	var pad_axis := _joy_axis(JOY_AXIS_LEFT_X, -1.0)
	var unsupported := InputEventAction.new()
	unsupported.action = &"fixture"
	var events: Array[InputEvent] = [key_a, pad_axis, key_left, pad_button, unsupported]
	var groups: Dictionary = MODEL.classify_events(events)
	if groups[MODEL.BindingSlot.KEYBOARD_PRIMARY] != [key_a]:
		failures.append("first keyboard event was not classified as primary")
	if groups[MODEL.BindingSlot.KEYBOARD_SECONDARY] != [key_left]:
		failures.append("remaining keyboard events were not classified as secondary")
	if groups[MODEL.BindingSlot.GAMEPAD] != [pad_axis, pad_button]:
		failures.append("joypad events did not retain relative order in the gamepad scheme")
	if groups[MODEL.UNSUPPORTED_GROUP] != [unsupported]:
		failures.append("unsupported input events were not preserved")


func _assert_slot_replacement(failures: Array[String]) -> void:
	var primary := _key(KEY_A)
	var secondary_one := _key(KEY_LEFT)
	var secondary_two := _mouse_button(MOUSE_BUTTON_LEFT)
	var gamepad_one := _joy_axis(JOY_AXIS_LEFT_X, -1.0)
	var gamepad_two := _joy_button(JOY_BUTTON_DPAD_LEFT)
	var unsupported := InputEventAction.new()
	unsupported.action = &"fixture"
	var events: Array[InputEvent] = [primary, secondary_one, gamepad_one, secondary_two, gamepad_two, unsupported]
	var replacement := _key(KEY_Q)

	var primary_result: Array[InputEvent] = MODEL.replace_slot_events(
		events,
		MODEL.BindingSlot.KEYBOARD_PRIMARY,
		[replacement]
	)
	var primary_groups: Dictionary = MODEL.classify_events(primary_result)
	var primary_bindings: Array[InputEvent] = primary_groups[MODEL.BindingSlot.KEYBOARD_PRIMARY]
	if not _is_single_key(primary_bindings, KEY_Q):
		failures.append("primary replacement did not replace only the primary binding")
	if primary_groups[MODEL.BindingSlot.KEYBOARD_SECONDARY] != [secondary_one, secondary_two]:
		failures.append("primary replacement changed the secondary scheme")
	if primary_groups[MODEL.BindingSlot.GAMEPAD] != [gamepad_one, gamepad_two]:
		failures.append("primary replacement changed the gamepad scheme")
	if primary_groups[MODEL.UNSUPPORTED_GROUP] != [unsupported]:
		failures.append("primary replacement dropped an unsupported event")

	var secondary_result: Array[InputEvent] = MODEL.replace_slot_events(
		events,
		MODEL.BindingSlot.KEYBOARD_SECONDARY,
		[replacement]
	)
	var secondary_groups: Dictionary = MODEL.classify_events(secondary_result)
	var secondary_bindings: Array[InputEvent] = secondary_groups[MODEL.BindingSlot.KEYBOARD_SECONDARY]
	if not _is_single_key(secondary_bindings, KEY_Q):
		failures.append("secondary replacement did not replace the whole secondary scheme")

	var gamepad_replacement := _joy_button(JOY_BUTTON_A)
	var gamepad_result: Array[InputEvent] = MODEL.replace_slot_events(
		events,
		MODEL.BindingSlot.GAMEPAD,
		[gamepad_replacement]
	)
	var gamepad_groups: Dictionary = MODEL.classify_events(gamepad_result)
	var gamepad_bindings: Array[InputEvent] = gamepad_groups[MODEL.BindingSlot.GAMEPAD]
	if (
		gamepad_bindings.size() != 1
		or not gamepad_bindings[0] is InputEventJoypadButton
		or (gamepad_bindings[0] as InputEventJoypadButton).button_index != JOY_BUTTON_A
	):
		failures.append("gamepad replacement did not replace the whole gamepad scheme")


func _assert_capture_compatibility_and_axis_normalization(failures: Array[String]) -> void:
	var mouse_press := _mouse_button(MOUSE_BUTTON_LEFT)
	if not MODEL.is_event_compatible(mouse_press, MODEL.BindingSlot.KEYBOARD_PRIMARY):
		failures.append("keyboard slot rejected a mouse-button press")
	if MODEL.is_event_compatible(mouse_press, MODEL.BindingSlot.GAMEPAD):
		failures.append("gamepad slot accepted a mouse-button press")
	var mouse_release := _mouse_button(MOUSE_BUTTON_LEFT)
	mouse_release.pressed = false
	if MODEL.is_event_compatible(mouse_release, MODEL.BindingSlot.KEYBOARD_SECONDARY):
		failures.append("keyboard slot accepted a mouse-button release")

	var quiet_axis := _joy_axis(JOY_AXIS_LEFT_Y, 0.49)
	if MODEL.is_event_compatible(quiet_axis, MODEL.BindingSlot.GAMEPAD):
		failures.append("gamepad slot accepted a sub-threshold axis motion")
	var active_axis := _joy_axis(JOY_AXIS_LEFT_Y, -0.75)
	if not MODEL.is_event_compatible(active_axis, MODEL.BindingSlot.GAMEPAD):
		failures.append("gamepad slot rejected an active axis motion")
	var normalized := MODEL.normalize_event(active_axis) as InputEventJoypadMotion
	if normalized == active_axis or normalized.axis != JOY_AXIS_LEFT_Y or normalized.axis_value != -1.0:
		failures.append("active joypad axis was not copied and normalized to its signed direction")


func _assert_action_filtering_and_order(failures: Array[String]) -> void:
	var source: Array[StringName] = [&"move_left", &"move_right", &"jump", &"dash"]
	var result: Array[StringName] = MODEL.discover_project_actions(
		source,
		[],
		[&"move_right"],
		[&"dash", &"unknown"]
	)
	if result != [&"dash", &"move_left", &"jump"]:
		failures.append("action exclusion and preferred order were not applied stably")
	var included: Array[StringName] = MODEL.discover_project_actions(
		source,
		[&"jump", &"move_right", &"unknown"],
		[&"move_right"],
		[]
	)
	if included != [&"jump"]:
		failures.append("explicit include and exclude lists were not intersected with project actions")


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


func _joy_axis(index: JoyAxis, value: float) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.axis = index
	event.axis_value = value
	return event


func _is_single_key(events: Array[InputEvent], code: Key) -> bool:
	return (
		events.size() == 1
		and events[0] is InputEventKey
		and (events[0] as InputEventKey).physical_keycode == code
	)
