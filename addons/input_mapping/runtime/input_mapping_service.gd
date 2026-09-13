class_name InputMappingService
extends Node

signal mapping_changed(action: StringName)
signal mappings_reset
signal persistence_failed(message: String)

const MODEL := preload("res://addons/input_mapping/core/input_mapping_model.gd")
const STORE := preload("res://addons/input_mapping/core/input_mapping_store.gd")
const DEFAULT_CONFIG_PATH := "user://input_mappings.cfg"

@export var auto_initialize := true

var _store: RefCounted = STORE.new()
var _config_path := DEFAULT_CONFIG_PATH
var _actions: Array[StringName] = []
var _defaults: Dictionary = {}
var _overrides: Dictionary = {}
var _initialized := false


func _ready() -> void:
	if auto_initialize:
		initialize()


func initialize(config_path: String = DEFAULT_CONFIG_PATH, source_actions: Array[StringName] = []) -> bool:
	_config_path = config_path
	_actions = MODEL.discover_project_actions(source_actions)
	_defaults.clear()
	_overrides.clear()
	for action: StringName in _actions:
		if InputMap.has_action(action):
			_defaults[action] = MODEL.duplicate_events(InputMap.action_get_events(action))
	_initialized = true
	return reload_overrides()


func get_actions() -> Array[StringName]:
	return _actions.duplicate()


func get_slot_events(action: StringName, slot: int) -> Array[InputEvent]:
	if not _is_known_action(action) or not _is_valid_slot(slot):
		return []
	return MODEL.get_slot_events(InputMap.action_get_events(action), slot)


func replace_slot(action: StringName, slot: int, event: InputEvent) -> bool:
	if not _is_known_action(action) or not _is_valid_slot(slot):
		return false
	if event == null or not MODEL.is_event_compatible(event, slot):
		return false
	var events: Array[InputEvent] = InputMap.action_get_events(action)
	_apply_action_events(action, MODEL.replace_slot_events(events, slot, [event]))
	_overrides[String(action)] = _serialize_action(action)
	mapping_changed.emit(action)
	return _save_overrides()


func clear_slot(action: StringName, slot: int) -> bool:
	if not _is_known_action(action) or not _is_valid_slot(slot):
		return false
	var events: Array[InputEvent] = InputMap.action_get_events(action)
	_apply_action_events(action, MODEL.replace_slot_events(events, slot, []))
	_overrides[String(action)] = _serialize_action(action)
	mapping_changed.emit(action)
	return _save_overrides()


func restore_defaults() -> bool:
	if not _initialized:
		return false
	for action: StringName in _actions:
		if _defaults.has(action) and InputMap.has_action(action):
			_apply_action_events(action, _defaults[action] as Array[InputEvent])
	_overrides.clear()
	var saved: bool = bool(_store.clear_overrides(_config_path))
	if not saved:
		persistence_failed.emit("Could not clear input mapping overrides at %s" % _config_path)
	mappings_reset.emit()
	return saved


func reload_overrides() -> bool:
	if not _initialized:
		return false
	for action: StringName in _actions:
		if _defaults.has(action) and InputMap.has_action(action):
			_apply_action_events(action, _defaults[action] as Array[InputEvent])
	var result: Dictionary = _store.load_overrides(_config_path)
	if not bool(result.get("ok", false)):
		var error := int(result.get("error", ERR_INVALID_DATA))
		push_warning("Could not load input mapping overrides from %s: %s" % [_config_path, error_string(error)])
		_overrides.clear()
		return false
	var loaded: Dictionary = result.get("actions", {})
	_overrides = loaded.duplicate(true)
	for action: StringName in _actions:
		var action_key := String(action)
		if not loaded.has(action_key):
			continue
		var record: Variant = loaded[action_key]
		if record is Dictionary and bool((record as Dictionary).get("customized", false)):
			_apply_record(action, record as Dictionary)
	return true


func _apply_record(action: StringName, record: Dictionary) -> void:
	var events: Array[InputEvent] = MODEL.duplicate_events(_defaults[action] as Array[InputEvent])
	for slot: int in [
		MODEL.BindingSlot.KEYBOARD_PRIMARY,
		MODEL.BindingSlot.KEYBOARD_SECONDARY,
		MODEL.BindingSlot.GAMEPAD,
	]:
		var key := _slot_key(slot)
		if not record.has(key):
			continue
		var raw_events: Variant = record[key]
		if not raw_events is Array:
			continue
		var valid_events: Array[InputEvent] = []
		var raw_array := raw_events as Array
		for value: Variant in raw_array:
			if value is InputEvent and MODEL.is_event_compatible(value as InputEvent, slot):
				valid_events.append(MODEL.normalize_event(value as InputEvent))
		if raw_array.is_empty() or not valid_events.is_empty():
			events = MODEL.replace_slot_events(events, slot, valid_events)
	_apply_action_events(action, events)


func _serialize_action(action: StringName) -> Dictionary:
	var events: Array[InputEvent] = InputMap.action_get_events(action)
	return {
		"customized": true,
		"primary": MODEL.get_slot_events(events, MODEL.BindingSlot.KEYBOARD_PRIMARY),
		"secondary": MODEL.get_slot_events(events, MODEL.BindingSlot.KEYBOARD_SECONDARY),
		"gamepad": MODEL.get_slot_events(events, MODEL.BindingSlot.GAMEPAD),
	}


func _save_overrides() -> bool:
	var saved: bool = bool(_store.save_overrides(_config_path, _overrides))
	if not saved:
		persistence_failed.emit("Could not save input mapping overrides at %s" % _config_path)
	return saved


func _apply_action_events(action: StringName, events: Array[InputEvent]) -> void:
	InputMap.action_erase_events(action)
	for event: InputEvent in events:
		InputMap.action_add_event(action, event)


func _slot_key(slot: int) -> String:
	match slot:
		MODEL.BindingSlot.KEYBOARD_PRIMARY:
			return "primary"
		MODEL.BindingSlot.KEYBOARD_SECONDARY:
			return "secondary"
		MODEL.BindingSlot.GAMEPAD:
			return "gamepad"
	return ""


func _is_known_action(action: StringName) -> bool:
	return _initialized and _actions.has(action) and InputMap.has_action(action)


func _is_valid_slot(slot: int) -> bool:
	return slot >= MODEL.BindingSlot.KEYBOARD_PRIMARY and slot <= MODEL.BindingSlot.GAMEPAD
