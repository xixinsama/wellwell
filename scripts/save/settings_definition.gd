class_name SettingsDefinition
extends RefCounted

const KIND_TOGGLE: StringName = &"toggle"
const KIND_OPTION: StringName = &"option"
const KIND_SLIDER: StringName = &"slider"
const KIND_ACTION: StringName = &"action"

var key: StringName
var section: StringName
var kind: StringName
var label_key: String
var description_key: String
var node_name: String
var default_value: Variant = null
var min_value := 0.0
var max_value := 1.0
var step := 0.05
var value_format := ""
var options: Array[Dictionary] = []
var action_label_key := ""


static func toggle(p_key: StringName, p_section: StringName, p_label_key: String, p_default: bool, p_node_name: String, p_description_key: String = "") -> SettingsDefinition:
	var definition := SettingsDefinition.new()
	definition.key = p_key
	definition.section = p_section
	definition.kind = KIND_TOGGLE
	definition.label_key = p_label_key
	definition.description_key = p_description_key
	definition.default_value = p_default
	definition.node_name = p_node_name
	return definition


static func option(p_key: StringName, p_section: StringName, p_label_key: String, p_default: String, p_node_name: String, p_options: Array[Dictionary], p_description_key: String = "") -> SettingsDefinition:
	var definition := SettingsDefinition.new()
	definition.key = p_key
	definition.section = p_section
	definition.kind = KIND_OPTION
	definition.label_key = p_label_key
	definition.description_key = p_description_key
	definition.default_value = p_default
	definition.node_name = p_node_name
	definition.options = p_options
	return definition


static func slider(p_key: StringName, p_section: StringName, p_label_key: String, p_default: float, p_node_name: String, p_min: float = 0.0, p_max: float = 1.0, p_step: float = 0.05, p_format: String = "", p_description_key: String = "") -> SettingsDefinition:
	var definition := SettingsDefinition.new()
	definition.key = p_key
	definition.section = p_section
	definition.kind = KIND_SLIDER
	definition.label_key = p_label_key
	definition.description_key = p_description_key
	definition.default_value = p_default
	definition.node_name = p_node_name
	definition.min_value = p_min
	definition.max_value = p_max
	definition.step = p_step
	definition.value_format = p_format
	return definition


static func action(p_key: StringName, p_section: StringName, p_label_key: String, p_node_name: String, p_action_label_key: String, p_description_key: String = "") -> SettingsDefinition:
	var definition := SettingsDefinition.new()
	definition.key = p_key
	definition.section = p_section
	definition.kind = KIND_ACTION
	definition.label_key = p_label_key
	definition.description_key = p_description_key
	definition.node_name = p_node_name
	definition.action_label_key = p_action_label_key
	return definition
