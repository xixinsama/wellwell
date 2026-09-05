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
	return failures

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

