class_name SettingsCatalog
extends RefCounted

const GENERAL: StringName = &"general"
const AUDIO: StringName = &"audio"
const GAMEPLAY: StringName = &"gameplay"
const CONTROLS: StringName = &"controls"

const SECTIONS: Array[Dictionary] = [
	{
		"id": GENERAL,
		"label_key": "SETTINGS_SECTION_GENERAL",
		"description_key": "SETTINGS_SECTION_GENERAL_DESC",
	},
	{
		"id": AUDIO,
		"label_key": "SETTINGS_SECTION_AUDIO",
		"description_key": "SETTINGS_SECTION_AUDIO_DESC",
	},
	{
		"id": GAMEPLAY,
		"label_key": "SETTINGS_SECTION_GAMEPLAY",
		"description_key": "SETTINGS_SECTION_GAMEPLAY_DESC",
	},
	{
		"id": CONTROLS,
		"label_key": "SETTINGS_SECTION_CONTROLS",
		"description_key": "SETTINGS_SECTION_CONTROLS_DESC",
	},
]

static var _definitions: Array[SettingsDefinition] = []


static func sections() -> Array[Dictionary]:
	return SECTIONS.duplicate(true)


static func section_metadata(section: StringName) -> Dictionary:
	for metadata: Dictionary in SECTIONS:
		if metadata["id"] == section:
			return metadata
	return {}


static func definitions() -> Array[SettingsDefinition]:
	if _definitions.is_empty():
		_build_definitions()
	return _definitions


static func definitions_for(section: StringName) -> Array[SettingsDefinition]:
	var result: Array[SettingsDefinition] = []
	for definition: SettingsDefinition in definitions():
		if definition.section == section:
			result.append(definition)
	return result


static func find_definition(key: StringName) -> SettingsDefinition:
	for definition: SettingsDefinition in definitions():
		if definition.key == key:
			return definition
	return null


static func default_values() -> Dictionary:
	var values := {}
	for definition: SettingsDefinition in definitions():
		if definition.kind != SettingsDefinition.KIND_ACTION:
			values[definition.key] = definition.default_value
	return values


static func _build_definitions() -> void:
	_definitions = [
		SettingsDefinition.option(
			&"locale",
			GENERAL,
			"SETTINGS_LANGUAGE",
			"zh_CN",
			"LanguageOption",
			[
				{"value": "en", "label_key": "SETTINGS_LANGUAGE_ENGLISH"},
				{"value": "zh_CN", "label_key": "SETTINGS_LANGUAGE_CHINESE"},
			]
		),
		SettingsDefinition.option(
			&"display_mode",
			GENERAL,
			"SETTINGS_DISPLAY_MODE",
			"windowed",
			"DisplayModeOption",
			[
				{"value": "windowed", "label_key": "SETTINGS_WINDOWED"},
				{"value": "fullscreen", "label_key": "SETTINGS_FULLSCREEN"},
			]
		),
		SettingsDefinition.slider(
			&"master_volume",
			AUDIO,
			"SETTINGS_MASTER_VOLUME",
			0.7,
			"MasterSlider",
			0.0,
			1.0,
			0.05,
			"percent"
		),
		SettingsDefinition.slider(
			&"music_volume",
			AUDIO,
			"SETTINGS_MUSIC_VOLUME",
			0.7,
			"MusicSlider",
			0.0,
			1.0,
			0.05,
			"percent"
		),
		SettingsDefinition.slider(
			&"sfx_volume",
			AUDIO,
			"SETTINGS_SFX_VOLUME",
			0.8,
			"SfxSlider",
			0.0,
			1.0,
			0.05,
			"percent"
		),
		SettingsDefinition.toggle(
			&"fog_enabled",
			GAMEPLAY,
			"SETTINGS_FOG",
			true,
			"FogToggle"
		),
		SettingsDefinition.toggle(
			&"camera_shake_enabled",
			GAMEPLAY,
			"SETTINGS_CAMERA_SHAKE",
			true,
			"CameraShakeToggle"
		),
		SettingsDefinition.toggle(
			&"one_way_drop_enabled",
			GAMEPLAY,
			"SETTINGS_ONE_WAY_DROP",
			true,
			"OneWayDropToggle"
		),
		SettingsDefinition.action(
			&"input_mapping",
			CONTROLS,
			"SETTINGS_INPUT_MAPPING",
			"InputMappingButton",
			"SETTINGS_INPUT_MAPPING_OPEN"
		),
	]
