extends Node

const SETTINGS_MANAGER := preload("res://scripts/save/global_settings_manager.gd")
const SAVE_SNAPSHOT := preload("res://addons/platformer_kit/save/save_snapshot.gd")

const MENU_TRANSLATION_PATH := "res://localization/menu.csv"
const REQUIRED_TRANSLATION_KEYS: Array[String] = [
	"MENU_TITLE",
	"MENU_START",
	"MENU_SETTINGS",
	"MENU_QUIT",
	"SLOTS_TITLE",
	"SLOT_EMPTY",
	"SLOT_CONTINUE",
	"SLOT_COPY",
	"SLOT_DELETE",
	"SLOT_START_FAILED",
	"WORLD_SELECT_TITLE",
	"WORLD_SELECT_SUBTITLE",
	"WORLD_SELECT_ENTER",
	"WORLD_SELECT_EMPTY",
	"SETTINGS_TITLE",
	"SETTINGS_NAV_HINT",
	"SETTINGS_SECTION_GENERAL",
	"SETTINGS_SECTION_GENERAL_DESC",
	"SETTINGS_SECTION_AUDIO",
	"SETTINGS_SECTION_AUDIO_DESC",
	"SETTINGS_SECTION_GAMEPLAY",
	"SETTINGS_SECTION_GAMEPLAY_DESC",
	"SETTINGS_SECTION_CONTROLS",
	"SETTINGS_SECTION_CONTROLS_DESC",
	"SETTINGS_LANGUAGE",
	"SETTINGS_DISPLAY_MODE",
	"SETTINGS_MASTER_VOLUME",
	"SETTINGS_MUSIC_VOLUME",
	"SETTINGS_SFX_VOLUME",
	"SETTINGS_FOG",
	"SETTINGS_CAMERA_SHAKE",
	"SETTINGS_ONE_WAY_DROP",
	"SETTINGS_INPUT_MAPPING",
	"INPUT_ACTION_MOVE_LEFT",
	"INPUT_ACTION_MOVE_RIGHT",
	"INPUT_ACTION_MOVE_UP",
	"INPUT_ACTION_MOVE_DOWN",
	"INPUT_ACTION_JUMP",
	"INPUT_ACTION_DASH",
	"INPUT_ACTION_INTERACT",
	"COMMON_BACK",
	"COMMON_CONFIRM",
	"COMMON_CANCEL",
]

func run() -> Array[String]:
	var failures: Array[String] = []
	_assert_translation_catalog(failures)
	_assert_main_menu_contract(failures)
	_assert_save_slots_contract(failures)
	_assert_settings_contract(failures)
	_assert_settings_api(failures)
	_assert_input_mapping_navigation_and_reset(failures)
	_assert_transactional_start_flow(failures)
	_assert_world_selection_flow(failures)
	return failures


class FakeStartManager extends Node:
	var selected_slot := 0
	var activate_count := 0
	var snapshot: RefCounted = SAVE_SNAPSHOT.new()
	func prepare_slot(slot: int) -> RefCounted:
		snapshot.slot = slot
		snapshot.world_id = "the_world"
		return snapshot
	func activate_snapshot(value: RefCounted) -> bool:
		activate_count += 1
		selected_slot = int(value.get("slot"))
		return true


class FakeGameRoot extends Node:
	var succeeds := false
	var start_count := 0
	var persistence_source: Node
	var started_world: WorldData
	func bind_persistence_source(value: Node) -> void:
		persistence_source = value
	func start_selected_snapshot(_snapshot: RefCounted, world: WorldData = null) -> bool:
		start_count += 1
		started_world = world
		return succeeds
	func get_last_start_errors() -> Array[String]:
		return ["fixture startup failure"]


class FakeSlots extends Control:
	var error_text := ""
	var show_count := 0
	func show_slots() -> void:
		show_count += 1
		show()
	func show_start_error(value: String) -> void:
		error_text = value
		show()


class FakeWorldSelect extends Control:
	var opened := false
	var saved_world_id := ""
	var error_text := ""
	func open_select(value: String = "") -> void:
		opened = true
		saved_world_id = value
		show()
	func show_start_error(value: String = "") -> void:
		error_text = value
		show()


class FakeSettings extends Node:
	var values := {
		"locale": "en",
		"display_mode": "windowed",
		"master_volume": 0.7,
		"music_volume": 0.7,
		"sfx_volume": 0.8,
		"fog_enabled": true,
		"camera_shake_enabled": true,
		"one_way_drop_enabled": true,
	}
	var reset_count := 0
	func get_value(key: StringName) -> Variant:
		return values.get(key)
	func set_value(key: StringName, value: Variant) -> void:
		values[key] = value
	func reset_defaults() -> void:
		reset_count += 1


class FakeInputMapping extends Node:
	signal mapping_changed(action: StringName)
	signal mappings_reset
	signal persistence_failed(message: String)
	var reset_count := 0
	func get_actions() -> Array[StringName]:
		return []
	func restore_defaults() -> bool:
		reset_count += 1
		mappings_reset.emit()
		return true

func _assert_translation_catalog(failures: Array[String]) -> void:
	if not FileAccess.file_exists(MENU_TRANSLATION_PATH):
		failures.append("menu translation CSV is missing")
		return
	var file := FileAccess.open(MENU_TRANSLATION_PATH, FileAccess.READ)
	var text := file.get_as_text()
	file.close()
	if not text.begins_with("keys,en,zh_CN"):
		failures.append("menu translation CSV has wrong locale columns")
	for key: String in REQUIRED_TRANSLATION_KEYS:
		if not text.contains("\n%s," % key):
			failures.append("menu translation key is missing: %s" % key)

func _assert_main_menu_contract(failures: Array[String]) -> void:
	_assert_scene_nodes("res://scenes/ui/main_menu.tscn", [
		"Title", "StartButton", "SettingsButton", "QuitButton", "SaveSlots", "WorldSelect"
	], failures)

func _assert_save_slots_contract(failures: Array[String]) -> void:
	_assert_scene_nodes("res://scenes/ui/save_slots.tscn", [
		"Title", "SlotList", "CopyDialog", "DeleteDialog", "ReturnButton"
	], failures)

func _assert_settings_contract(failures: Array[String]) -> void:
	var packed := load("res://scenes/ui/settings.tscn") as PackedScene
	var settings := packed.instantiate() as Control
	add_child(settings)
	for node_name: String in [
		"GeneralTab", "AudioTab", "GameplayTab", "ControlsTab", "PageHost",
		"LanguageOption", "DisplayModeOption", "MasterSlider", "MusicSlider",
		"SfxSlider", "FogToggle", "CameraShakeToggle", "OneWayDropToggle",
		"InputMappingButton", "InputMappingMenu", "BackButton"
	]:
		if settings.find_child(node_name, true, false) == null:
			failures.append("res://scenes/ui/settings.tscn is missing node %s" % node_name)
	settings.free()

func _assert_settings_api(failures: Array[String]) -> void:
	var manager: Node = SETTINGS_MANAGER.new()
	for method_name: String in [
		"get_locale", "set_locale", "set_display_mode", "is_camera_shake_enabled",
		"set_camera_shake_enabled", "is_one_way_drop_enabled", "set_one_way_drop_enabled"
	]:
		if not manager.has_method(method_name):
			failures.append("settings API is missing: %s" % method_name)
	manager.free()


func _assert_input_mapping_navigation_and_reset(failures: Array[String]) -> void:
	var packed := load("res://scenes/ui/settings.tscn") as PackedScene
	var settings := packed.instantiate() as Control
	add_child(settings)
	var fake_settings := FakeSettings.new()
	var fake_input := FakeInputMapping.new()
	settings.add_child(fake_settings)
	settings.add_child(fake_input)
	if not settings.has_method("bind_settings_dependencies"):
		failures.append("settings menu is missing injectable input mapping dependencies")
		settings.queue_free()
		return
	settings.call("bind_settings_dependencies", fake_settings, fake_input)
	settings.call("open_menu")
	settings.call("_open_input_mapping")
	var panel := settings.get_node("Panel") as Control
	var input_menu := settings.get_node("InputMappingMenu") as Control
	if panel.visible or not input_menu.visible:
		failures.append("input mapping entry did not replace the ordinary settings panel")
	var parent_back_count := 0
	settings.back_requested.connect(func() -> void: parent_back_count += 1)
	var cancel := InputEventAction.new()
	cancel.action = &"ui_cancel"
	cancel.pressed = true
	settings.call("_unhandled_input", cancel)
	if parent_back_count != 0:
		failures.append("parent settings menu handled ui_cancel while input mapping was open")
	input_menu.call("_request_back")
	if not panel.visible or input_menu.visible:
		failures.append("input mapping Back did not restore the ordinary settings panel")
	settings.call("_reset_defaults")
	if fake_settings.reset_count != 1 or fake_input.reset_count != 1:
		failures.append("global Restore Defaults did not reset ordinary and input settings")
	settings.queue_free()


func _assert_transactional_start_flow(failures: Array[String]) -> void:
	var menu_script := load("res://scripts/ui/main_menu.gd") as Script
	var menu := menu_script.new() as Control
	if not menu.has_method("bind_start_dependencies"):
		failures.append("main menu is missing injectable transactional startup dependencies")
		menu.free()
		return
	var slots := FakeSlots.new()
	menu.add_child(slots)
	menu.set("save_slots", slots)
	var manager := FakeStartManager.new()
	var game_root := FakeGameRoot.new()
	menu.add_child(manager)
	menu.add_child(game_root)
	menu.call("bind_start_dependencies", manager, game_root)
	menu.show()
	menu.call("_start_game", 2)
	if not menu.visible or manager.selected_slot != 0 or manager.activate_count != 0:
		failures.append("failed world startup hid the menu or activated the save slot")
	if slots.error_text.is_empty():
		failures.append("failed world startup did not surface an error in save slots")
	game_root.succeeds = true
	menu.call("_start_game", 2)
	if menu.visible or manager.selected_slot != 2 or manager.activate_count != 1:
		failures.append("successful world startup did not activate the slot and hide the menu")
	if game_root.persistence_source != manager:
		failures.append("main menu did not inject persistence into the world session")
	menu.free()

func _assert_world_selection_flow(failures: Array[String]) -> void:
	var menu_script := load("res://scripts/ui/main_menu.gd") as Script
	var menu := menu_script.new() as Control
	var slots := FakeSlots.new()
	var world_select := FakeWorldSelect.new()
	var manager := FakeStartManager.new()
	var game_root := FakeGameRoot.new()
	menu.add_child(slots)
	menu.add_child(world_select)
	menu.add_child(manager)
	menu.add_child(game_root)
	menu.set("save_slots", slots)
	menu.set("world_select", world_select)
	menu.call("bind_start_dependencies", manager, game_root)
	menu.show()

	menu.call("_open_world_select", 2)
	if not world_select.opened or world_select.saved_world_id != "the_world":
		failures.append("save slot did not open map selection with its saved world")
	if slots.visible:
		failures.append("save slots stayed visible behind map selection")

	var world := load("res://resources/worlds/main_world.tres") as WorldData
	game_root.succeeds = true
	menu.call("_on_world_chosen", world)
	if game_root.started_world != world:
		failures.append("selected map was not passed to the world session")
	if menu.visible:
		failures.append("successful map start did not hide the menu")

	game_root.succeeds = false
	world_select.error_text = ""
	menu.show()
	world_select.show()
	menu.call("_start_game", 2, world)
	if world_select.error_text.is_empty():
		failures.append("failed map start did not surface an error in map selection")
	menu.free()


func _assert_scene_nodes(path: String, names: Array[String], failures: Array[String]) -> void:
	var packed: PackedScene = load(path) as PackedScene
	if packed == null:
		failures.append("could not load UI scene: %s" % path)
		return
	var scene := packed.instantiate()
	for node_name: String in names:
		if scene.find_child(node_name, true, false) == null:
			failures.append("%s is missing node %s" % [path, node_name])
	scene.free()
