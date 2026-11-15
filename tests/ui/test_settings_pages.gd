extends Node

const CATALOG := preload("res://scripts/save/settings_catalog.gd")
const DEFINITION := preload("res://scripts/save/settings_definition.gd")
const SETTINGS_MANAGER := preload("res://scripts/save/global_settings_manager.gd")
const SETTINGS_STORE := preload("res://scripts/save/global_settings_store.gd")
const SETTINGS_SCENE := preload("res://scenes/ui/settings.tscn")
const PAGE_SCENE := preload("res://scenes/ui/settings/settings_page.tscn")
const MASTER_BUS := 0


func run() -> Array[String]:
	var failures: Array[String] = []
	_assert_catalog(failures)
	_assert_generic_settings_api(failures)
	_assert_video_settings(failures)
	_assert_focus_mute(failures)
	_assert_pages_and_rows(failures)
	_assert_category_switching(failures)
	return failures


func _assert_catalog(failures: Array[String]) -> void:
	var sections: Array = CATALOG.sections()
	if sections.size() != 4:
		failures.append("settings catalog should expose four sections")
	var section_ids: Array[StringName] = []
	for metadata: Dictionary in sections:
		section_ids.append(metadata["id"])
	for expected: StringName in [CATALOG.GAME, CATALOG.AUDIO, CATALOG.VIDEO, CATALOG.CONTROLS]:
		if not section_ids.has(expected):
			failures.append("settings catalog is missing section: %s" % expected)
	var keys: Array[StringName] = []
	for definition: SettingsDefinition in CATALOG.definitions():
		if keys.has(definition.key):
			failures.append("duplicate setting key: %s" % definition.key)
		keys.append(definition.key)
		if not section_ids.has(definition.section):
			failures.append("setting %s points at unknown section %s" % [definition.key, definition.section])
		if definition.kind not in [
			DEFINITION.KIND_TOGGLE,
			DEFINITION.KIND_OPTION,
			DEFINITION.KIND_SLIDER,
			DEFINITION.KIND_ACTION,
		]:
			failures.append("setting %s has unknown kind %s" % [definition.key, definition.kind])
	var controls: Array[SettingsDefinition] = CATALOG.definitions_for(CATALOG.CONTROLS)
	if controls.size() != 1 or controls[0].kind != DEFINITION.KIND_ACTION:
		failures.append("controls section should contain the input mapping action")
	for expected_key: StringName in [
		&"locale", &"fog_enabled", &"camera_shake_enabled", &"one_way_drop_enabled",
		&"atmosphere_enabled",
		&"master_volume", &"music_volume", &"sfx_volume", &"mute_on_focus_loss",
		&"display_mode", &"resolution_scale", &"vsync_enabled", &"fps_limit",
		&"input_mapping",
	]:
		if CATALOG.find_definition(expected_key) == null:
			failures.append("settings catalog is missing key: %s" % expected_key)


func _assert_generic_settings_api(failures: Array[String]) -> void:
	var path := "user://settings_catalog_test_%d.json" % Time.get_ticks_usec()
	var manager: Node = SETTINGS_MANAGER.new()
	manager.setup_store(SETTINGS_STORE.new(path), false)
	manager.load_settings()
	manager.set_value(&"master_volume", 2.0)
	if not is_equal_approx(float(manager.get_value(&"master_volume")), 1.0):
		failures.append("generic settings API did not clamp slider values")
	manager.set_value(&"fog_enabled", false)
	if bool(manager.get_value(&"fog_enabled")):
		failures.append("generic settings API did not store toggle values")
	manager.set_value(&"display_mode", "sideways")
	if String(manager.get_value(&"display_mode")) != "windowed":
		failures.append("generic settings API accepted an unknown option value")
	manager.set_value(&"not_a_setting", 1)
	var persisted: Dictionary = SETTINGS_STORE.new(path).load_settings()
	if not is_equal_approx(float(persisted.get("master_volume", 0.0)), 1.0):
		failures.append("generic settings API did not persist values")
	if bool(persisted.get("fog_enabled", true)):
		failures.append("persisted settings ignored the generic toggle write")
	manager.reset_defaults()
	if not is_equal_approx(float(manager.get_value(&"master_volume")), 0.7):
		failures.append("reset_defaults did not restore catalog defaults")
	if not bool(manager.get_value(&"fog_enabled")):
		failures.append("reset_defaults did not restore gameplay defaults")
	manager.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _assert_video_settings(failures: Array[String]) -> void:
	var path := "user://settings_video_test_%d.json" % Time.get_ticks_usec()
	var manager: Node = SETTINGS_MANAGER.new()
	manager.setup_store(SETTINGS_STORE.new(path), false)
	manager.load_settings()
	if manager.get_resolution_scale() != 4:
		failures.append("default resolution scale should be 4X")
	manager.set_value(&"resolution_scale", "8")
	if manager.get_resolution_scale() != 8:
		failures.append("resolution scale did not accept 8X")
	manager.set_value(&"fps_limit", "60")
	if manager.get_fps_limit() != 60:
		failures.append("fps limit did not accept 60")
	if Engine.max_fps != 60 or Engine.physics_ticks_per_second != 60:
		failures.append("fps limit did not sync render and physics rates")
	manager.set_value(&"fps_limit", "144")
	if Engine.max_fps != 144 or Engine.physics_ticks_per_second != 144:
		failures.append("fps limit did not sync the 144 rate")
	manager.set_value(&"vsync_enabled", false)
	if manager.is_vsync_enabled():
		failures.append("vsync toggle did not store its value")
	manager.reset_defaults()
	if Engine.max_fps != 120 or Engine.physics_ticks_per_second != 120:
		failures.append("reset_defaults did not restore the 120 rate")
	if manager.get_resolution_scale() != 4:
		failures.append("reset_defaults did not restore 4X")
	manager.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _assert_focus_mute(failures: Array[String]) -> void:
	var path := "user://settings_mute_test_%d.json" % Time.get_ticks_usec()
	var manager: Node = SETTINGS_MANAGER.new()
	manager.setup_store(SETTINGS_STORE.new(path), false)
	manager.load_settings()
	manager.set_value(&"master_volume", 0.7)
	manager.set_value(&"mute_on_focus_loss", true)
	manager._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	if not AudioServer.is_bus_mute(MASTER_BUS):
		failures.append("focus loss did not mute the master bus")
	manager._notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	if AudioServer.is_bus_mute(MASTER_BUS):
		failures.append("focus return did not restore the master bus")
	manager.set_value(&"mute_on_focus_loss", false)
	manager._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	if AudioServer.is_bus_mute(MASTER_BUS):
		failures.append("focus mute stayed active after being disabled")
	manager._notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	manager.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _assert_pages_and_rows(failures: Array[String]) -> void:
	for section: StringName in [CATALOG.GAME, CATALOG.AUDIO, CATALOG.VIDEO, CATALOG.CONTROLS]:
		var page := PAGE_SCENE.instantiate() as SettingsPage
		page.section = section
		add_child(page)
		var definitions: Array[SettingsDefinition] = CATALOG.definitions_for(section)
		for definition: SettingsDefinition in definitions:
			if page.find_child(definition.node_name, true, false) == null:
				failures.append("settings page %s is missing row control %s" % [section, definition.node_name])
		var rows := page.get("_entries") as Array
		if rows.size() != definitions.size():
			failures.append("settings page %s built %d rows for %d definitions" % [section, rows.size(), definitions.size()])
		page.free()


func _assert_category_switching(failures: Array[String]) -> void:
	var settings := SETTINGS_SCENE.instantiate() as Control
	add_child(settings)
	settings.call("open_menu")
	var expected_pages := {
		"game": "GamePage",
		"audio": "AudioPage",
		"video": "VideoPage",
		"controls": "ControlsPage",
	}
	for section: String in expected_pages:
		settings.call("_select_section", StringName(section))
		for other: String in expected_pages:
			var page := settings.find_child(expected_pages[other], true, false) as Control
			var should_be_visible := other == section
			if page.visible != should_be_visible:
				failures.append("settings category %s did not show only %s" % [section, expected_pages[section]])
		var tab := settings.find_child("%sTab" % section.capitalize(), true, false) as Button
		if tab != null and not tab.button_pressed:
			failures.append("settings tab %s stayed inactive after selection" % section)
	var audio_tab := settings.find_child("AudioTab", true, false) as Button
	if audio_tab != null:
		audio_tab.button_pressed = true
	var audio_page := settings.find_child("AudioPage", true, false) as Control
	if not audio_page.visible:
		failures.append("selecting the Audio tab did not reveal the Audio page")
	settings.free()
