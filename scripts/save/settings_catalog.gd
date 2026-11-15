class_name SettingsCatalog
extends RefCounted

const GAME: StringName = &"game"
const AUDIO: StringName = &"audio"
const VIDEO: StringName = &"video"
const CONTROLS: StringName = &"controls"

const SECTIONS: Array[Dictionary] = [
	{
		"id": GAME,
		"label_key": "SETTINGS_SECTION_GAME",
	},
	{
		"id": AUDIO,
		"label_key": "SETTINGS_SECTION_AUDIO",
	},
	{
		"id": VIDEO,
		"label_key": "SETTINGS_SECTION_VIDEO",
	},
	{
		"id": CONTROLS,
		"label_key": "SETTINGS_SECTION_CONTROLS",
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
			GAME,
			"SETTINGS_LANGUAGE",
			"zh_CN",
			"LanguageOption",
			[
				{"value": "en", "label_key": "SETTINGS_LANGUAGE_ENGLISH"},
				{"value": "zh_CN", "label_key": "SETTINGS_LANGUAGE_CHINESE"},
			],
			"SETTINGS_DESC_LANGUAGE"
		),
		SettingsDefinition.toggle(
			&"fog_enabled",
			GAME,
			"SETTINGS_FOG",
			true,
			"FogToggle",
			"SETTINGS_DESC_FOG"
		),
		SettingsDefinition.toggle(
			&"atmosphere_enabled",
			GAME,
			"SETTINGS_ATMOSPHERE",
			true,
			"AtmosphereToggle",
			"SETTINGS_DESC_ATMOSPHERE"
		),
		SettingsDefinition.toggle(
			&"camera_shake_enabled",
			GAME,
			"SETTINGS_CAMERA_SHAKE",
			true,
			"CameraShakeToggle",
			"SETTINGS_DESC_CAMERA_SHAKE"
		),
		SettingsDefinition.toggle(
			&"one_way_drop_enabled",
			GAME,
			"SETTINGS_ONE_WAY_DROP",
			true,
			"OneWayDropToggle",
			"SETTINGS_DESC_ONE_WAY_DROP"
		),
		SettingsDefinition.toggle(
			&"one_way_occludes_sight",
			GAME,
			"SETTINGS_ONE_WAY_SIGHT",
			true,
			"OneWaySightToggle",
			"SETTINGS_DESC_ONE_WAY_SIGHT"
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
			&"mute_on_focus_loss",
			AUDIO,
			"SETTINGS_MUTE_ON_FOCUS",
			true,
			"MuteOnFocusToggle",
			"SETTINGS_DESC_MUTE_ON_FOCUS"
		),
		SettingsDefinition.option(
			&"display_mode",
			VIDEO,
			"SETTINGS_DISPLAY_MODE",
			"windowed",
			"DisplayModeOption",
			[
				{"value": "windowed", "label_key": "SETTINGS_WINDOWED"},
				{"value": "fullscreen", "label_key": "SETTINGS_FULLSCREEN"},
				{"value": "borderless", "label_key": "SETTINGS_BORDERLESS"},
			]
		),
		SettingsDefinition.option(
			&"resolution_scale",
			VIDEO,
			"SETTINGS_RESOLUTION",
			"4",
			"ResolutionOption",
			[
				{"value": "2", "label_key": "SETTINGS_RESOLUTION_2X"},
				{"value": "4", "label_key": "SETTINGS_RESOLUTION_4X"},
				{"value": "8", "label_key": "SETTINGS_RESOLUTION_8X"},
				{"value": "16", "label_key": "SETTINGS_RESOLUTION_16X"},
			],
			"SETTINGS_DESC_RESOLUTION"
		),
		SettingsDefinition.toggle(
			&"vsync_enabled",
			VIDEO,
			"SETTINGS_VSYNC",
			true,
			"VsyncToggle"
		),
		SettingsDefinition.option(
			&"fps_limit",
			VIDEO,
			"SETTINGS_FPS_LIMIT",
			"120",
			"FpsLimitOption",
			[
				{"value": "30", "label_key": "SETTINGS_FPS_30"},
				{"value": "60", "label_key": "SETTINGS_FPS_60"},
				{"value": "120", "label_key": "SETTINGS_FPS_120"},
				{"value": "144", "label_key": "SETTINGS_FPS_144"},
			],
			"SETTINGS_DESC_FPS"
		),
		SettingsDefinition.action(
			&"input_mapping",
			CONTROLS,
			"SETTINGS_INPUT_MAPPING",
			"InputMappingButton",
			"SETTINGS_INPUT_MAPPING_OPEN",
			"SETTINGS_DESC_INPUT_MAPPING"
		),
	]
