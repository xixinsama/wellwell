class_name InputEventFormatter
extends RefCounted


static func format_events(events: Array[InputEvent]) -> String:
	if events.is_empty():
		return _translate("INPUT_MAPPING_UNBOUND")
	var labels: PackedStringArray = []
	for event: InputEvent in events:
		labels.append(format_event(event))
	return " / ".join(labels)


static func format_event(event: InputEvent) -> String:
	if event is InputEventKey:
		return _format_key(event as InputEventKey)
	if event is InputEventMouseButton:
		return _format_mouse(event as InputEventMouseButton)
	if event is InputEventJoypadButton:
		return _format_joy_button(event as InputEventJoypadButton)
	if event is InputEventJoypadMotion:
		return _format_joy_axis(event as InputEventJoypadMotion)
	return event.as_text()


static func _format_key(event: InputEventKey) -> String:
	var label := event.as_text_physical_keycode() if event.physical_keycode != KEY_NONE else event.as_text_keycode()
	return label if not label.is_empty() else event.as_text()


static func _format_mouse(event: InputEventMouseButton) -> String:
	var keys := {
		MOUSE_BUTTON_LEFT: "INPUT_MAPPING_MOUSE_LEFT",
		MOUSE_BUTTON_RIGHT: "INPUT_MAPPING_MOUSE_RIGHT",
		MOUSE_BUTTON_MIDDLE: "INPUT_MAPPING_MOUSE_MIDDLE",
		MOUSE_BUTTON_XBUTTON1: "INPUT_MAPPING_MOUSE_BACK",
		MOUSE_BUTTON_XBUTTON2: "INPUT_MAPPING_MOUSE_FORWARD",
		MOUSE_BUTTON_WHEEL_UP: "INPUT_MAPPING_MOUSE_WHEEL_UP",
		MOUSE_BUTTON_WHEEL_DOWN: "INPUT_MAPPING_MOUSE_WHEEL_DOWN",
	}
	var key := String(keys.get(event.button_index, ""))
	return _translate(key) if not key.is_empty() else event.as_text()


static func _format_joy_button(event: InputEventJoypadButton) -> String:
	var keys := {
		JOY_BUTTON_A: "INPUT_MAPPING_PAD_A",
		JOY_BUTTON_B: "INPUT_MAPPING_PAD_B",
		JOY_BUTTON_X: "INPUT_MAPPING_PAD_X",
		JOY_BUTTON_Y: "INPUT_MAPPING_PAD_Y",
		JOY_BUTTON_BACK: "INPUT_MAPPING_PAD_BACK",
		JOY_BUTTON_START: "INPUT_MAPPING_PAD_START",
		JOY_BUTTON_LEFT_SHOULDER: "INPUT_MAPPING_PAD_LEFT_SHOULDER",
		JOY_BUTTON_RIGHT_SHOULDER: "INPUT_MAPPING_PAD_RIGHT_SHOULDER",
		JOY_BUTTON_LEFT_STICK: "INPUT_MAPPING_PAD_LEFT_STICK",
		JOY_BUTTON_RIGHT_STICK: "INPUT_MAPPING_PAD_RIGHT_STICK",
		JOY_BUTTON_DPAD_UP: "INPUT_MAPPING_DPAD_UP",
		JOY_BUTTON_DPAD_DOWN: "INPUT_MAPPING_DPAD_DOWN",
		JOY_BUTTON_DPAD_LEFT: "INPUT_MAPPING_DPAD_LEFT",
		JOY_BUTTON_DPAD_RIGHT: "INPUT_MAPPING_DPAD_RIGHT",
	}
	var key := String(keys.get(event.button_index, ""))
	return _translate(key) if not key.is_empty() else event.as_text()


static func _format_joy_axis(event: InputEventJoypadMotion) -> String:
	var negative := event.axis_value < 0.0
	var key := ""
	match event.axis:
		JOY_AXIS_LEFT_X:
			key = "INPUT_MAPPING_LEFT_STICK_LEFT" if negative else "INPUT_MAPPING_LEFT_STICK_RIGHT"
		JOY_AXIS_LEFT_Y:
			key = "INPUT_MAPPING_LEFT_STICK_UP" if negative else "INPUT_MAPPING_LEFT_STICK_DOWN"
		JOY_AXIS_RIGHT_X:
			key = "INPUT_MAPPING_RIGHT_STICK_LEFT" if negative else "INPUT_MAPPING_RIGHT_STICK_RIGHT"
		JOY_AXIS_RIGHT_Y:
			key = "INPUT_MAPPING_RIGHT_STICK_UP" if negative else "INPUT_MAPPING_RIGHT_STICK_DOWN"
		JOY_AXIS_TRIGGER_LEFT:
			key = "INPUT_MAPPING_LEFT_TRIGGER"
		JOY_AXIS_TRIGGER_RIGHT:
			key = "INPUT_MAPPING_RIGHT_TRIGGER"
	return _translate(key) if not key.is_empty() else event.as_text()


static func _translate(key: String) -> String:
	return String(TranslationServer.translate(StringName(key)))
