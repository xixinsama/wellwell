extends Node

const SETTINGS_MANAGER := preload("res://scripts/save/global_settings_manager.gd")

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
	"SETTINGS_TITLE",
	"SETTINGS_LANGUAGE",
	"SETTINGS_DISPLAY_MODE",
	"SETTINGS_MASTER_VOLUME",
	"SETTINGS_MUSIC_VOLUME",
	"SETTINGS_SFX_VOLUME",
	"SETTINGS_FOG",
	"SETTINGS_CAMERA_SHAKE",
	"SETTINGS_ONE_WAY_DROP",
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
	_assert_transactional_start_flow(failures)
	return failures


class FakeStartManager extends Node:
	var selected_slot := 0
	var activate_count := 0
	var snapshot := RefCounted.new()
	func prepare_slot(slot: int) -> RefCounted:
		snapshot.set_meta("slot", slot)
		return snapshot
	func activate_snapshot(value: RefCounted) -> bool:
		activate_count += 1
		selected_slot = int(value.get_meta("slot"))
		return true


class FakeGameRoot extends Node:
	var succeeds := false
	var start_count := 0
	func start_selected_snapshot(_snapshot: RefCounted) -> bool:
		start_count += 1
		return succeeds
	func get_last_start_errors() -> Array[String]:
		return ["fixture startup failure"]


class FakeSlots extends Control:
	var error_text := ""
	func show_start_error(value: String) -> void:
		error_text = value

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
		"Title", "StartButton", "SettingsButton", "QuitButton", "SaveSlots"
	], failures)

func _assert_save_slots_contract(failures: Array[String]) -> void:
	_assert_scene_nodes("res://scenes/ui/save_slots.tscn", [
		"Title", "SlotList", "CopyDialog", "DeleteDialog", "ReturnButton"
	], failures)

func _assert_settings_contract(failures: Array[String]) -> void:
	_assert_scene_nodes("res://scenes/ui/settings.tscn", [
		"LanguageOption", "DisplayModeOption", "MasterSlider", "MusicSlider",
		"SfxSlider", "FogToggle", "CameraShakeToggle", "OneWayDropToggle", "BackButton"
	], failures)

func _assert_settings_api(failures: Array[String]) -> void:
	var manager: Node = SETTINGS_MANAGER.new()
	for method_name: String in [
		"get_locale", "set_locale", "set_display_mode", "is_camera_shake_enabled",
		"set_camera_shake_enabled", "is_one_way_drop_enabled", "set_one_way_drop_enabled"
	]:
		if not manager.has_method(method_name):
			failures.append("settings API is missing: %s" % method_name)
	manager.free()


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
