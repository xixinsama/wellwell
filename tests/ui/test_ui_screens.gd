extends Node

## Merged test suite. Every inner class below is one original test file,
## kept in its own class so fixtures and helper names stay isolated. Do not
## add logic here: split a class back into its own file when it grows.

## tests/ui/test_menu_contract.gd
class MenuContractCase extends Node:
	func run() -> Array[String]:
		var failures: Array[String] = []
		for path: String in [
			"res://scenes/ui/main_menu.tscn",
			"res://scenes/ui/save_slots.tscn",
			"res://scenes/ui/world_select.tscn",
			"res://scenes/ui/settings.tscn",
		]:
			if not ResourceLoader.exists(path, "PackedScene"):
				failures.append("missing UI scene: %s" % path)
		return failures


## tests/ui/test_collection_screen.gd
class CollectionScreenCase extends Node:
	const SCREEN_SCENE := preload("res://scenes/ui/collection_screen.tscn")


	func run() -> Array[String]:
		var failures: Array[String] = []
		var registry := get_node_or_null("/root/Collectibles")
		if registry == null:
			return ["Collectibles autoload is missing"]
		registry.call("reset")
		registry.set("current_world_id", "test_collection_screen")
		registry.call("register_number", 1)
		registry.call("register_number", 2)
		registry.call("register_number", 3)
		registry.call("collect_number", 2)

		var screen := SCREEN_SCENE.instantiate() as Control
		add_child(screen)
		if String(screen.call("get_badge_text")) != "图鉴 1 / 3":
			failures.append("collection badge text is wrong: %s" % screen.call("get_badge_text"))

		screen.call("open")
		if not bool(screen.call("is_open")):
			failures.append("collection screen did not open")
		if not get_tree().paused:
			failures.append("collection screen did not pause the game")

		var grid := screen.find_child("Grid", true, false) as GridContainer
		if grid == null or grid.get_child_count() != 3:
			failures.append("collection grid did not list every number")
		elif not bool(grid.get_child(1).get_meta(&"collected", false)):
			failures.append("the collected number is not marked in the grid")
		elif bool(grid.get_child(0).get_meta(&"collected", true)):
			failures.append("a missing number is marked collected")
		var count_label := screen.find_child("Count", true, false) as Label
		if count_label == null or count_label.text != "1 / 3":
			failures.append("collection count is wrong: %s" % (count_label.text if count_label != null else "<none>"))

		screen.call("close")
		if bool(screen.call("is_open")) or get_tree().paused:
			failures.append("collection screen did not close and unpause cleanly")

		# The rebindable toggle action opens and closes it too.
		var toggle := InputEventAction.new()
		toggle.action = &"collection_toggle"
		toggle.pressed = true
		screen.call("_unhandled_input", toggle)
		if not bool(screen.call("is_open")):
			failures.append("collection_toggle did not open the screen")
		var cancel := InputEventAction.new()
		cancel.action = &"ui_cancel"
		cancel.pressed = true
		screen.call("_unhandled_input", cancel)
		if bool(screen.call("is_open")) or get_tree().paused:
			failures.append("ui_cancel did not close the collection screen")

		registry.call("reset")
		if screen.find_child("Badge", true, false).visible:
			failures.append("collection badge stayed visible without a world")
		screen.queue_free()
		return failures


## tests/ui/test_interaction_prompt.gd
class InteractionPromptCase extends Node:
	const PROMPT_SCENE := preload("res://scenes/ui/interaction_prompt.tscn")


	class FakeController extends Node:
		var available := true
		var candidate: Node2D

		func is_available() -> bool:
			return available

		func get_candidate() -> Node:
			return candidate


	func run() -> Array[String]:
		var failures: Array[String] = []
		var actor := Node2D.new()
		actor.name = "FakePlayer"
		var controller := FakeController.new()
		controller.name = "InteractionController"
		actor.add_child(controller)
		actor.add_to_group(&"player")
		add_child(actor)
		var target := Node2D.new()
		target.position = Vector2(120.0, 90.0)
		add_child(target)
		var prompt := PROMPT_SCENE.instantiate() as Control
		add_child(prompt)
		prompt.call("bind_actor", actor)

		controller.candidate = target
		prompt.call("_process", 0.0)
		if not prompt.visible:
			failures.append("interaction prompt did not show for a candidate")
		if String(prompt.call("get_displayed_glyph")) != "E":
			failures.append(
				"interaction prompt did not show the keyboard binding: %s"
				% prompt.call("get_displayed_glyph")
			)

		controller.candidate = null
		prompt.call("_process", 0.0)
		if prompt.visible:
			failures.append("interaction prompt stayed visible without a candidate")

		controller.available = false
		controller.candidate = target
		prompt.call("_process", 0.0)
		if prompt.visible:
			failures.append("interaction prompt ignored an unavailable controller")

		controller.available = true
		var pad_event := InputEventJoypadButton.new()
		pad_event.button_index = JOY_BUTTON_X
		pad_event.pressed = true
		prompt.call("_input", pad_event)
		prompt.call("_process", 0.0)
		if String(prompt.call("get_displayed_glyph")) != "X":
			failures.append(
				"interaction prompt did not switch to the gamepad glyph: %s"
				% prompt.call("get_displayed_glyph")
			)

		prompt.queue_free()
		actor.queue_free()
		target.queue_free()
		return failures


## tests/ui/test_world_select.gd
class WorldSelectCase extends Node:
	const SCENE_PATH := "res://scenes/ui/world_select.tscn"
	const CATALOG_PATH := "res://resources/worlds/world_catalog.tres"


	func run() -> Array[String]:
		var failures: Array[String] = []
		_assert_catalog(failures)
		_assert_selection_ui(failures)
		_assert_empty_catalog(failures)
		return failures


	func _assert_catalog(failures: Array[String]) -> void:
		var catalog := load(CATALOG_PATH) as WorldCatalog
		if catalog == null:
			failures.append("world catalog resource is missing")
			return
		var worlds := catalog.get_worlds()
		if worlds.is_empty():
			failures.append("world catalog exposes no worlds")
			return
		var ids: Array[String] = []
		for world: WorldData in worlds:
			if world.display_name.is_empty():
				failures.append("world catalog entries need display names: %s" % world.world_id)
			if ids.has(world.world_id):
				failures.append("world catalog repeats a world: %s" % world.world_id)
			ids.append(world.world_id)
		# The catalog is authored and grows with the project, so only the reference
		# worlds are required; the count and any later entries are up to the author.
		for required: String in ["the_world", "main_world", "test_world", "loop_world"]:
			if not ids.has(required):
				failures.append("world catalog dropped the reference world: %s" % required)


	func _assert_selection_ui(failures: Array[String]) -> void:
		var packed := load(SCENE_PATH) as PackedScene
		if packed == null:
			failures.append("world selection scene is missing")
			return
		var catalog := load(CATALOG_PATH) as WorldCatalog
		var expected_rows := 0 if catalog == null else catalog.get_worlds().size()
		var ui := packed.instantiate() as Control
		add_child(ui)
		ui.call("open_select", "main_world")
		var list := ui.find_child("WorldList", true, false) as VBoxContainer
		if list == null:
			failures.append("world selection list is missing")
			ui.queue_free()
			return
		var rows := list.find_children("WorldRow_*", "HBoxContainer", true, false)
		if rows.size() != expected_rows:
			failures.append("world selection did not build one row per world")
			ui.queue_free()
			return
		var chosen: Array[WorldData] = []
		ui.connect("world_chosen", func(world: WorldData) -> void: chosen.append(world))
		var enter := rows[0].find_child("EnterButton", true, false) as Button
		if enter == null:
			failures.append("world row is missing its enter button")
		else:
			enter.pressed.emit()
		if chosen.size() != 1 or chosen[0].world_id != "the_world":
			failures.append("world row did not emit its world")
		if ui.visible:
			failures.append("world selection stayed visible after choosing a world")
		var back_count: Array[int] = [0]
		ui.connect("back_requested", func() -> void: back_count[0] += 1)
		ui.call("_request_back")
		if back_count[0] != 1:
			failures.append("world selection back button did not emit")
		ui.queue_free()


	## A missing or unloadable catalog must fall back to the empty state instead of
	## dying inside the typed-array assignment.
	func _assert_empty_catalog(failures: Array[String]) -> void:
		var packed := load(SCENE_PATH) as PackedScene
		if packed == null:
			return
		var ui := packed.instantiate() as Control
		ui.set("catalog", null)
		add_child(ui)
		ui.call("open_select")
		var list := ui.find_child("WorldList", true, false) as VBoxContainer
		if list == null:
			failures.append("world selection list is missing without a catalog")
		else:
			var children := list.get_children()
			if children.size() != 1 or not (children[0] is Label):
				failures.append("world selection did not show its empty state without a catalog")
		ui.queue_free()


## tests/ui/test_settings_pages.gd
class SettingsPagesCase extends Node:
	const CATALOG := preload("res://game/save/settings_catalog.gd")
	const DEFINITION := preload("res://game/save/settings_definition.gd")
	const SETTINGS_MANAGER := preload("res://game/save/global_settings_manager.gd")
	const SETTINGS_STORE := preload("res://game/save/global_settings_store.gd")
	const SETTINGS_SCENE := preload("res://scenes/ui/settings.tscn")
	const PAGE_SCENE := preload("res://scenes/ui/settings/settings_page.tscn")
	const MASTER_BUS := 0


	func run() -> Array[String]:
		var failures: Array[String] = []
		_assert_catalog(failures)
		_assert_realtime_translation(failures)
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
			&"atmosphere_enabled", &"celeste_momentum_enabled", &"realtime_save_enabled",
			&"master_volume", &"music_volume", &"sfx_volume", &"mute_on_focus_loss",
			&"display_mode", &"resolution_scale", &"vsync_enabled", &"fps_limit",
			&"input_mapping",
		]:
			if CATALOG.find_definition(expected_key) == null:
				failures.append("settings catalog is missing key: %s" % expected_key)
		var momentum: SettingsDefinition = CATALOG.find_definition(&"celeste_momentum_enabled")
		if momentum == null or bool(momentum.default_value):
			failures.append("Celeste momentum must default to off")
		var realtime: SettingsDefinition = CATALOG.find_definition(&"realtime_save_enabled")
		if realtime == null:
			failures.append("settings catalog is missing realtime_save_enabled")
		elif realtime.section != CATALOG.GAME or realtime.kind != DEFINITION.KIND_TOGGLE:
			failures.append("realtime save must be a Game toggle")
		elif bool(realtime.default_value):
			failures.append("realtime save must default to off")


	func _assert_realtime_translation(failures: Array[String]) -> void:
		var source := load("res://localization/menu.zh_CN.translation") as Translation
		if source == null:
			failures.append("Chinese menu translation is missing")
			return
		if source.get_message("SETTINGS_REALTIME_SAVE") != "实时存档":
			failures.append("realtime save label is missing from the Chinese translation")
		if source.get_message("SETTINGS_DESC_REALTIME_SAVE").is_empty():
			failures.append("realtime save description is missing from the Chinese translation")


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
		if manager.has_method("is_realtime_save_enabled") and manager.call("is_realtime_save_enabled"):
			failures.append("realtime save must start disabled")
		manager.set_value(&"realtime_save_enabled", true)
		if not manager.has_method("is_realtime_save_enabled") or not bool(manager.call("is_realtime_save_enabled")):
			failures.append("realtime save setting did not apply through the settings API")
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


func run() -> Array[String]:
	var failures: Array[String] = []
	failures.append_array(_run_case(MenuContractCase.new()))
	failures.append_array(_run_case(CollectionScreenCase.new()))
	failures.append_array(_run_case(InteractionPromptCase.new()))
	failures.append_array(_run_case(WorldSelectCase.new()))
	failures.append_array(_run_case(SettingsPagesCase.new()))
	return failures


func _run_case(test: Node) -> Array[String]:
	add_child(test)
	var result: Array = test.call("run")
	test.queue_free()
	var failures: Array[String] = []
	failures.assign(result)
	return failures
